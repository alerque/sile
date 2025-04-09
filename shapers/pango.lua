-- This shaper package is deprecated and should only be used as an
-- example of how to create alternative shaper backends, in comparison
-- with the harfbuzz shaper.
local lgi = require("lgi")
require("string")
local pango = lgi.Pango
local fm = lgi.PangoCairo.FontMap.get_default()
local pango_context = lgi.Pango.FontMap.create_context(fm)
pango_context:set_round_glyph_positions(false)  -- We want exact positions
pango_context:set_language(pango.Language.get_default())
pango_context:set_base_dir(pango.Direction.LTR)  -- Default to left-to-right

local base = require("shapers.base")

local palcache = {}

local function _shape (text, item)
   local offset = item.offset
   local length = item.length
   local analysis = item.analysis

   SU.debug("pango", "Shape input:", pl.pretty.write {
      text = text,
      offset = offset,
      length = length,
      has_analysis = analysis ~= nil,
      analysis_font = analysis and analysis.font or "no font",
      analysis_lang = analysis and analysis.language or "no language"
   })

   local shaped_text = string.sub(text, 1 + offset, 1 + offset + length)
   SU.debug("pango", "Shaping text segment:", shaped_text)

   local pgs = pango.GlyphString.new()

   -- Ensure we have a valid font in the analysis
   if not (analysis and analysis.font) then
      SU.debug("pango", "No font in analysis, creating fallback")
      local desc = pango.FontDescription.new()
      desc:set_family("serif")
      desc:set_size(12 * pango.SCALE)
      analysis = pango.Analysis.new()
      analysis.font = pango_context:load_font(desc)
   end

   -- Shape with explicit length
   pango.shape(shaped_text, string.len(shaped_text), analysis, pgs)

   SU.debug("pango", "Shaped result:", pl.pretty.write {
      num_glyphs = pgs.num_glyphs,
      has_glyphs = pgs.glyphs ~= nil,
      analysis_font = analysis.font,
      text_length = string.len(shaped_text)
   })

   return pgs
end

local shaper = pl.class(base)
shaper._name = "pango"

-- TODO: refactor so method accepts self
function shaper.getFace (options)
   SU.debug("pango", "Getting face for options:", pl.pretty.write(options))

   -- First get the actual font face using SILE's font manager
   local face = SILE.fontManager:face(options)
   if not face then
      SU.error("Couldn't find face '" .. options.family .. "'")
   end

   SU.debug("pango", "SILE font face:", pl.pretty.write {
      family = face.family,
      filename = face.filename,
      subfamily = face.subfamily,
      fullname = face.fullname
   })

   -- Create a font description from the actual font data
   local desc = pango.FontDescription.new()
   desc:set_family(face.family)
   desc:set_size(options.size * pango.SCALE)
   if options.weight then
      desc:set_weight(tonumber(options.weight))
   end

   -- Load the actual font into Pango
   local font = pango_context:load_font(desc)
   if not font then
      SU.error("Pango couldn't load font: " .. face.family)
   end

   -- Debug font information
   local font_desc = font:describe()
   SU.debug("pango", "Loaded Pango font details:", pl.pretty.write {
      family = font_desc:get_family(),
      size = font_desc:get_size() / pango.SCALE,
      weight = font_desc:get_weight(),
      loaded = font:get_face() ~= nil,
      metrics = pl.pretty.write(font:get_metrics())
   })

   -- -- Try to get font file path through fontconfig
   -- local fc_font = font:get_face()
   -- if fc_font then
   --    SU.debug("pango", "Font file path:", fc_font:get_filename())
   -- end

   -- Create and return the attribute list with the font
   local pal = pango.AttrList.new()
   pal:insert(pango.attr_font_desc_new(desc))

   if options.language then
      pal:insert(pango.attr_language_new(pango.Language.from_string(options.language)))
   end

   return pal, font
end

function shaper:shapeToken (text, options)
   SU.debug("pango", "Shaping text:", text, "with options:", pl.pretty.write(options))

   local pal = SILE.font.cache(options, self.getFace)
   SU.debug("pango", "Got PAL:", pal)

   local items = pango.itemize(pango_context, text, 0, string.len(text), pal, nil)
   SU.debug("pango", "Itemization result count:", #items)

   local rv = {}
   local twidth = SILE.types.length()

   for i = 1, #items do
      local item = items[i]
      local pgs = _shape(text, item)
      local font = item.analysis.font

      if not font then
         SU.debug("pango", "No font in analysis for item:", i)
         goto continue
      end

      SU.debug("pango", "Processing glyphs for item:", i)
      for g = 0, (pgs.num_glyphs or 0) - 1 do
         local glyph = pgs.glyphs[g]
         if glyph then
            local rect = font:get_glyph_extents(glyph.glyph)
            table.insert(rv, {
               height = -rect.y / 1024,
               depth = (rect.y + rect.height) / 1024,
               width = rect.width / 1024,
               glyph = glyph.glyph,
               pgs = pgs,
               font = font,
            })
         end
      end

      ::continue::
   end

   SU.debug("pango", "Final shaped result:", pl.pretty.write(rv))
   return rv
end

function shaper:addShapedGlyphToNnodeValue (nnodevalue, shapedglyph)
   nnodevalue.pgs = shapedglyph.pgs
   nnodevalue.font = shapedglyph.font
end

return shaper
