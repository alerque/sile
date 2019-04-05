#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <hb.h>
#include <hb-ot.h>
#include <hb-ft.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "silewin32.h"

/* The following function stolen from XeTeX_ext.c */
static hb_tag_t
read_tag_with_param(const char* cp, int* param)
{
  const char* cp2;
  hb_tag_t tag;
  int i;

  cp2 = cp;
  while (*cp2 && (*cp2 != ':') && (*cp2 != ';') && (*cp2 != ',') && (*cp2 != '='))
    ++cp2;

  tag = hb_tag_from_string(cp, cp2 - cp);

  cp = cp2;
  if (*cp == '=') {
    int neg = 0;
    ++cp;
    if (*cp == '-') {
      ++neg;
      ++cp;
    }
    while (*cp >= '0' && *cp <= '9') {
      *param = *param * 10 + *cp - '0';
      ++cp;
    }
    if (neg)
      *param = -(*param);
  }

  return tag;
}

static hb_feature_t* scan_feature_string(const char* cp1, int* ret) {
  hb_feature_t* features = NULL;
  hb_tag_t  tag;  
  int nFeatures = 0;
  const char* cp2;
  const char* cp3;
  while (*cp1) {
    if ((*cp1 == ':') || (*cp1 == ';') || (*cp1 == ','))
      ++cp1;
    while ((*cp1 == ' ') || (*cp1 == '\t')) /* skip leading whitespace */
      ++cp1;
    if (*cp1 == 0)  /* break if end of string */
      break;

    cp2 = cp1;
    while (*cp2 && (*cp2 != ':') && (*cp2 != ';') && (*cp2 != ','))
      ++cp2;
    
    if (*cp1 == '+') {
      int param = 0;
      tag = read_tag_with_param(cp1 + 1, &param);
      features = realloc(features, (nFeatures + 1) * sizeof(hb_feature_t));
      features[nFeatures].tag = tag;
      features[nFeatures].start = 0;
      features[nFeatures].end = (unsigned int) -1;
      if (param == 0)
        param++;
      features[nFeatures].value = param;
      nFeatures++;
      goto next_option;
    }
    
    if (*cp1 == '-') {
      ++cp1;
      tag = hb_tag_from_string(cp1, cp2 - cp1);
      features = realloc(features, (nFeatures + 1) * sizeof(hb_feature_t));
      features[nFeatures].tag = tag;
      features[nFeatures].start = 0;
      features[nFeatures].end = (unsigned int) -1;
      features[nFeatures].value = 0;
      nFeatures++;
      goto next_option;
    }
    
  bad_option:
    //fontfeaturewarning(cp1, cp2 - cp1, 0, 0);
  
  next_option:
    cp1 = cp2;
  }
  *ret = nFeatures;
  return features;
}

static char** scan_shaper_list(char* cp1) {
  char** res = NULL;
  char* cp2;
  int n_elems = 0;
  int i;
  while (*cp1) {
    if ((*cp1 == ':') || (*cp1 == ';') || (*cp1 == ','))
      ++cp1;
    while ((*cp1 == ' ') || (*cp1 == '\t')) /* skip leading whitespace */
      ++cp1;
    if (*cp1 == 0)  /* break if end of string */
      break;

    cp2 = cp1;
    while (*cp2 && (*cp2 != ':') && (*cp2 != ';') && (*cp2 != ','))
      ++cp2;
    if (*cp2 == 0) {
      res = realloc (res, sizeof (char*) * ++n_elems);
      res[n_elems-1] = cp1;
      break;
    } else {
      *cp2 = '\0';
      res = realloc (res, sizeof (char*) * ++n_elems);
      res[n_elems-1] = cp1;
    }
    cp1 = cp2+1;
  }
  res = realloc (res, sizeof (char*) * (n_elems+1));
  res[n_elems] = 0;
  return res;
}

int shape (lua_State *L) {
    size_t font_l;
    const char * text = luaL_checkstring(L, 1);
    const char * font_s = luaL_checklstring(L, 2, &font_l);
    unsigned int font_index = luaL_checknumber(L, 3);
    const char * script = luaL_checkstring(L, 4);
    const char * direction_s = luaL_checkstring(L, 5);
    const char * lang = luaL_checkstring(L, 6);
    double point_size = luaL_checknumber(L, 7);
    const char * featurestring = luaL_checkstring(L, 8);
    char * shaper_list_string = luaL_checkstring(L, 9);
    char ** shaper_list = NULL;
    if (strlen(shaper_list_string) > 0) {
      shaper_list = scan_shaper_list(shaper_list_string);
    }
    hb_segment_properties_t segment_props;
    hb_shape_plan_t *shape_plan;

    hb_direction_t direction;
    hb_feature_t* features;
    int nFeatures = 0;
    unsigned int glyph_count = 0;
    hb_font_t *hbFont;
    hb_buffer_t *buf;
    hb_glyph_info_t *glyph_info;
    hb_glyph_position_t *glyph_pos;
    unsigned int j;

    features = scan_feature_string(featurestring, &nFeatures);

    if (!strcasecmp(direction_s,"RTL"))
      direction = HB_DIRECTION_RTL;
    else if (!strcasecmp(direction_s,"TTB"))
      direction = HB_DIRECTION_TTB;
    else
      direction = HB_DIRECTION_LTR;

    hb_blob_t* blob = hb_blob_create (font_s, font_l, HB_MEMORY_MODE_WRITABLE, (void*)font_s, NULL);
    hb_face_t* hbFace = hb_face_create (blob, font_index);
    hbFont = hb_font_create (hbFace);
    unsigned int upem = hb_face_get_upem(hbFace);
    hb_font_set_scale(hbFont, upem, upem);

    /* Harfbuzz's support for OT fonts is great, but
       there's currently no support for CFF fonts, so
       downgrade to Freetype for those. */
    if (strncmp(font_s, "OTTO", 4) == 0 || strncmp(font_s, "ttcf", 4) == 0) {
      hb_ft_font_set_funcs(hbFont);
    } else {
      hb_ot_font_set_funcs(hbFont);
    }

    buf = hb_buffer_create();
    hb_buffer_add_utf8(buf, text, strlen(text), 0, strlen(text));

    hb_buffer_set_script(buf, hb_tag_from_string(script, strlen(script)));
    hb_buffer_set_direction(buf, direction);
    hb_buffer_set_language(buf, hb_language_from_string(lang,strlen(lang)));

    hb_buffer_guess_segment_properties(buf);
    hb_buffer_get_segment_properties(buf, &segment_props);
    shape_plan = hb_shape_plan_create_cached(hbFace, &segment_props, features, nFeatures, shaper_list);
    int res = hb_shape_plan_execute(shape_plan, hbFont, buf, features, nFeatures);

    if (direction == HB_DIRECTION_RTL) {
      hb_buffer_reverse(buf); /* URGH */
    }
    glyph_info   = hb_buffer_get_glyph_infos(buf, &glyph_count);
    glyph_pos    = hb_buffer_get_glyph_positions(buf, &glyph_count);
    lua_checkstack(L, glyph_count);
    for (j = 0; j < glyph_count; ++j) {
      char namebuf[255];
      hb_glyph_extents_t extents = {0,0,0,0};
      hb_font_get_glyph_extents(hbFont, glyph_info[j].codepoint, &extents);

      lua_newtable(L);
      lua_pushstring(L, "name");
      hb_font_get_glyph_name( hbFont, glyph_info[j].codepoint, namebuf, 255 );
      lua_pushstring(L, namebuf);
      lua_settable(L, -3);

      /* We don't apply x-offset and y-offsets for TTB, which
      is arguably a bug. We should. The reason we don't is that
      Harfbuzz assumes that you want to shift the character from a
      top-center baseline to a bottom-left baseline, and gives you
      offsets which do that. We don't want to do that so we ignore the
      offsets. I'm told there is a way of configuring HB's idea of the
      baseline, and we should use that and take out this condition. */
      if (direction != HB_DIRECTION_TTB) {
        if (glyph_pos[j].x_offset) {
          lua_pushstring(L, "x_offset");
          lua_pushnumber(L, glyph_pos[j].x_offset * point_size / upem);
          lua_settable(L, -3);
        }

        if (glyph_pos[j].y_offset) {
          lua_pushstring(L, "y_offset");
          lua_pushnumber(L, glyph_pos[j].y_offset * point_size / upem);
          lua_settable(L, -3);
        }
      }

      lua_pushstring(L, "gid");
      lua_pushinteger(L, glyph_info[j].codepoint);
      lua_settable(L, -3);
      lua_pushstring(L, "index");
      lua_pushinteger(L, glyph_info[j].cluster);
      lua_settable(L, -3);

      double height = extents.y_bearing * point_size / upem;
      double tHeight = extents.height * point_size / upem;
      double width = glyph_pos[j].x_advance * point_size / upem;

      /* The PDF model expects us to make positioning adjustments
      after a glyph is painted. For this we need to know the natural
      glyph advance. libtexpdf will use this to compute the adjustment. */
      double glyphAdvance = hb_font_get_glyph_h_advance(hbFont, glyph_info[j].codepoint) * point_size / upem;

      if (direction == HB_DIRECTION_TTB) {
        height = -glyph_pos[j].y_advance * point_size / upem;
        tHeight = -height; /* Set depth to 0 - depth has no meaning for TTB */
        width = glyphAdvance;
        glyphAdvance = height;
      }
      lua_pushstring(L, "glyphAdvance");
      lua_pushnumber(L, glyphAdvance);
      lua_settable(L, -3);

      lua_pushstring(L, "width");
      lua_pushnumber(L, width);
      lua_settable(L, -3);

      lua_pushstring(L, "height");
      lua_pushnumber(L, height);
      lua_settable(L, -3);
      lua_pushstring(L, "depth");
      lua_pushnumber(L, -tHeight - height);
      lua_settable(L, -3);
    }
    /* Cleanup */
    hb_buffer_destroy(buf);
    hb_font_destroy(hbFont);
    hb_shape_plan_destroy(shape_plan);

    free(features);
    return glyph_count;
}

int get_harfbuzz_version (lua_State *L) {
  unsigned int major;
  unsigned int minor;
  unsigned int micro;
  char version[256];
  hb_version(&major, &minor, &micro);
  sprintf(version, "%i.%i.%i", major, minor, micro);
  lua_pushstring(L, version);
  return 1;
}

int list_shapers (lua_State *L) {
  const char **shaper_list = hb_shape_list_shapers ();
  int i = 0;

  for (; *shaper_list; shaper_list++) {
    i++;
    lua_pushstring(L, *shaper_list);
  }
  return i;
}

int get_table (lua_State *L) {
  size_t font_l, tag_l;
  const char * font_s = luaL_checklstring(L, 1, &font_l);
  unsigned int font_index = luaL_checknumber(L, 2);
  const char * tag_s = luaL_checklstring(L, 3, &tag_l);

  hb_blob_t * blob = hb_blob_create (font_s, font_l, HB_MEMORY_MODE_WRITABLE, (void*)font_s, NULL);
  hb_face_t * face = hb_face_create (blob, font_index);
  hb_blob_t * table = hb_face_reference_table(face, hb_tag_from_string(tag_s, tag_l));

  unsigned int table_l;
  const char * table_s = hb_blob_get_data(table, &table_l);

  lua_pushlstring(L, table_s, table_l);

  hb_blob_destroy(table);
  hb_face_destroy(face);
  hb_blob_destroy(blob);

  return 1;
}

#ifdef HB_OT_TAG_MATH
struct MathConstantNameEntry {
  hb_ot_math_constant_t id;
  char *name;
};

int get_math_constants(lua_State *L) {
  static struct MathConstantNameEntry constantNames_percent[] = {
    { HB_OT_MATH_CONSTANT_SCRIPT_PERCENT_SCALE_DOWN, "ScriptPercentScaleDown" },
    { HB_OT_MATH_CONSTANT_SCRIPT_SCRIPT_PERCENT_SCALE_DOWN, "ScriptScriptPercentScaleDown" },
  };
  static struct MathConstantNameEntry constantNames_number[] = {
    { HB_OT_MATH_CONSTANT_DELIMITED_SUB_FORMULA_MIN_HEIGHT, "DelimitedScriptSubFormulaMinHeight" },
    { HB_OT_MATH_CONSTANT_DISPLAY_OPERATOR_MIN_HEIGHT, "DisplayOperatorMinHeight" },
    { HB_OT_MATH_CONSTANT_MATH_LEADING, "MathLeading" },
    { HB_OT_MATH_CONSTANT_AXIS_HEIGHT, "AxisHeight" },
    { HB_OT_MATH_CONSTANT_ACCENT_BASE_HEIGHT, "AccentBaseHeight" },
    { HB_OT_MATH_CONSTANT_FLATTENED_ACCENT_BASE_HEIGHT, "FlattenedAccentBaseHeight" },
    { HB_OT_MATH_CONSTANT_SUBSCRIPT_SHIFT_DOWN, "SubscriptShiftDown" },
    { HB_OT_MATH_CONSTANT_SUBSCRIPT_TOP_MAX, "SubscriptTopMax" },
    { HB_OT_MATH_CONSTANT_SUBSCRIPT_BASELINE_DROP_MIN, "SubscriptBaselineDropMin" },
    { HB_OT_MATH_CONSTANT_SUPERSCRIPT_SHIFT_UP, "SuperscriptShiftUp" },
    { HB_OT_MATH_CONSTANT_SUPERSCRIPT_SHIFT_UP_CRAMPED, "SuperscriptShiftUpCramped" },
    { HB_OT_MATH_CONSTANT_SUPERSCRIPT_BOTTOM_MIN, "SuperscriptBottomMin" },
    { HB_OT_MATH_CONSTANT_SUPERSCRIPT_BASELINE_DROP_MAX, "SuperscriptBaselineDropMax" },
    { HB_OT_MATH_CONSTANT_SUB_SUPERSCRIPT_GAP_MIN, "ScriptSubSuperscriptGapMin" },
    { HB_OT_MATH_CONSTANT_SUPERSCRIPT_BOTTOM_MAX_WITH_SUBSCRIPT, "SuperscriptBottomMaxWithSubscript" },
    { HB_OT_MATH_CONSTANT_SPACE_AFTER_SCRIPT, "SpaceAfterScript" },
    { HB_OT_MATH_CONSTANT_UPPER_LIMIT_GAP_MIN, "UpperLimitGapMin" },
    { HB_OT_MATH_CONSTANT_UPPER_LIMIT_BASELINE_RISE_MIN, "UpperLimitBaselineRiseMin" },
    { HB_OT_MATH_CONSTANT_LOWER_LIMIT_GAP_MIN, "LowerLimitGapMin" },
    { HB_OT_MATH_CONSTANT_LOWER_LIMIT_BASELINE_DROP_MIN, "LowerLimitBaselineDropMin" },
    { HB_OT_MATH_CONSTANT_STACK_TOP_SHIFT_UP, "StackTopShiftUp" },
    { HB_OT_MATH_CONSTANT_STACK_TOP_DISPLAY_STYLE_SHIFT_UP, "StackTopDisplayStyleShiftUp" },
    { HB_OT_MATH_CONSTANT_STACK_BOTTOM_SHIFT_DOWN, "StackBottomShiftDown" },
    { HB_OT_MATH_CONSTANT_STACK_BOTTOM_DISPLAY_STYLE_SHIFT_DOWN, "StackBottomDisplayStyleShiftDown" },
    { HB_OT_MATH_CONSTANT_STACK_GAP_MIN, "StackGapMin" },
    { HB_OT_MATH_CONSTANT_STACK_DISPLAY_STYLE_GAP_MIN, "StackDisplayStyleGapMin" },
    { HB_OT_MATH_CONSTANT_STRETCH_STACK_TOP_SHIFT_UP, "StretchStackTopShiftUp" },
    { HB_OT_MATH_CONSTANT_STRETCH_STACK_BOTTOM_SHIFT_DOWN, "StretchStackBottomShiftDown" },
    { HB_OT_MATH_CONSTANT_STRETCH_STACK_GAP_ABOVE_MIN, "StretchStackGapAboveMin" },
    { HB_OT_MATH_CONSTANT_STRETCH_STACK_GAP_BELOW_MIN, "StretchStackGapBelowMin" },
    { HB_OT_MATH_CONSTANT_FRACTION_NUMERATOR_SHIFT_UP, "FractionNumberatorShiftUp" },
    { HB_OT_MATH_CONSTANT_FRACTION_NUMERATOR_DISPLAY_STYLE_SHIFT_UP, "FractionNumberatorDisplayStyleShiftUp" },
    { HB_OT_MATH_CONSTANT_FRACTION_DENOMINATOR_SHIFT_DOWN, "FractionDenominatorShiftDown" },
    { HB_OT_MATH_CONSTANT_FRACTION_DENOMINATOR_DISPLAY_STYLE_SHIFT_DOWN, "FractionDenominatorDisplayStyleShiftDown" },
    { HB_OT_MATH_CONSTANT_FRACTION_NUMERATOR_GAP_MIN, "FractionNumberatorGapMin" },
    { HB_OT_MATH_CONSTANT_FRACTION_NUM_DISPLAY_STYLE_GAP_MIN, "FractionNumDisplayStyleGapMin" },
    { HB_OT_MATH_CONSTANT_FRACTION_RULE_THICKNESS, "FractionRuleThickness" },
    { HB_OT_MATH_CONSTANT_FRACTION_DENOMINATOR_GAP_MIN, "FractionDenominatorGapMin" },
    { HB_OT_MATH_CONSTANT_FRACTION_DENOM_DISPLAY_STYLE_GAP_MIN, "FractionDenomDisplayStyleGapMin" },
    { HB_OT_MATH_CONSTANT_SKEWED_FRACTION_HORIZONTAL_GAP, "SkewedFractionHorizontalGap" },
    { HB_OT_MATH_CONSTANT_SKEWED_FRACTION_VERTICAL_GAP, "SkewedFractionVerticalGap" },
    { HB_OT_MATH_CONSTANT_OVERBAR_VERTICAL_GAP, "OverbarVerticalGap" },
    { HB_OT_MATH_CONSTANT_OVERBAR_RULE_THICKNESS, "OverbarRuleThickness" },
    { HB_OT_MATH_CONSTANT_OVERBAR_EXTRA_ASCENDER, "OverbarExtraAscender" },
    { HB_OT_MATH_CONSTANT_UNDERBAR_VERTICAL_GAP, "UnderbarVerticalGap" },
    { HB_OT_MATH_CONSTANT_UNDERBAR_RULE_THICKNESS, "UnderbarRuleThickness" },
    { HB_OT_MATH_CONSTANT_UNDERBAR_EXTRA_DESCENDER, "UnderbarExtraDescender" },
    { HB_OT_MATH_CONSTANT_RADICAL_VERTICAL_GAP, "RadicalVerticalGap" },
    { HB_OT_MATH_CONSTANT_RADICAL_DISPLAY_STYLE_VERTICAL_GAP, "RadicalDisplayStyleVerticalGap" },
    { HB_OT_MATH_CONSTANT_RADICAL_RULE_THICKNESS, "RadicalRuleThickness" },
    { HB_OT_MATH_CONSTANT_RADICAL_EXTRA_ASCENDER, "RadicalExtraAscender" },
    { HB_OT_MATH_CONSTANT_RADICAL_KERN_BEFORE_DEGREE, "RadicalKernBeforeDegree" },
    { HB_OT_MATH_CONSTANT_RADICAL_KERN_AFTER_DEGREE, "RadicalKernAfterDegree" },
    { HB_OT_MATH_CONSTANT_RADICAL_DEGREE_BOTTOM_RAISE_PERCENT, "RadicalDegreeBottomRaisePercent" },
  };

  size_t font_l;
  const char * font_s = luaL_checklstring(L, 1, &font_l);
  unsigned int font_index = luaL_checknumber(L, 2);
  double point_size = luaL_checknumber(L, 3);

  hb_blob_t * blob = hb_blob_create (font_s, font_l, HB_MEMORY_MODE_WRITABLE, (void*)font_s, NULL);
  hb_face_t * face = hb_face_create (blob, font_index);
  hb_font_t * font = hb_font_create (face);
  unsigned int upem = hb_face_get_upem(face);

  if (hb_ot_math_has_data(face)) {
    lua_newtable(L);
    for (int i = 0; i < sizeof(constantNames_percent) / sizeof(struct MathConstantNameEntry); ++i) {
      hb_ot_math_constant_t constantId = constantNames_percent[i].id;
      char *constantName = constantNames_percent[i].name;

      hb_position_t value = hb_ot_math_get_constant(font, constantId);

      lua_pushstring(L, constantName);
      lua_pushnumber(L, value / 100.0);
      lua_settable(L, -3);
    }
    for (int i = 0; i < sizeof(constantNames_number) / sizeof(struct MathConstantNameEntry); ++i) {
      hb_ot_math_constant_t constantId = constantNames_number[i].id;
      char *constantName = constantNames_number[i].name;

      hb_position_t value = hb_ot_math_get_constant(font, constantId);

      lua_pushstring(L, constantName);
      lua_pushnumber(L, value * point_size / upem);
      lua_settable(L, -3);
    }
  } else {
    lua_pushnil(L);
  }
  
  hb_font_destroy(font);
  hb_face_destroy(face);
  hb_blob_destroy(blob);
  return 1;
}
#endif

#if !defined LUA_VERSION_NUM
/* Lua 5.0 */
#define luaL_Reg luaL_reg
#endif

#if !defined LUA_VERSION_NUM || LUA_VERSION_NUM==501
/*
** Adapted from Lua 5.2.0
*/
static void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
  luaL_checkstack(L, nup+1, "too many upvalues");
  for (; l->name != NULL; l++) {  /* fill the table with given functions */
    int i;
    lua_pushstring(L, l->name);
    for (i = 0; i < nup; i++)  /* copy upvalues to the top */
      lua_pushvalue(L, -(nup+1));
    lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
    lua_settable(L, -(nup + 3));
  }
  lua_pop(L, nup);  /* remove upvalues */
}
#endif

static const struct luaL_Reg lib_table [] = {
  {"_shape", shape},
  {"version", get_harfbuzz_version},
  {"shapers", list_shapers},
  {"get_table", get_table},
#ifdef HB_OT_TAG_MATH
  {"get_math_constants", get_math_constants},
#endif
  {NULL, NULL}
};

int luaopen_justenoughharfbuzz (lua_State *L) {
  lua_newtable(L);
  luaL_setfuncs(L, lib_table, 0);
  //lua_setglobal(L, "harfbuzz");
  return 1;
}

