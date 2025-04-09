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

   SU.debug("pango", "Shape input:", {
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
   -- Make sure we're passing the font from the analysis
   if analysis and analysis.font then
      pango.shape(shaped_text, -1, analysis, pgs)
   else
      -- Try fallback if no font in analysis
      local desc = pango.FontDescription.new()
      desc:set_family("serif") -- fallback font
      desc:set_size(12 * pango.SCALE)
      local font = pango_context:load_font(desc)
      analysis = pango.Analysis.new()
      analysis.font = font
      pango.shape(shaped_text, -1, analysis, pgs)
   end

   SU.debug("pango", "Shaped result:", {
      num_glyphs = pgs.num_glyphs,
      has_glyphs = pgs.glyphs ~= nil,
      glyphs_table = pgs.glyphs and pl.pretty.write(pgs.glyphs) or "no glyphs"
   })

   return pgs
end

local shaper = pl.class(base)
shaper._name = "pango"

-- TODO: refactor so method accepts self
function shaper.getFace (options)
   SU.debug("pango", "Getting face for options:", pl.pretty.write(options))

   local pal = pango.AttrList.new()

   -- Create a font description
   local desc = pango.FontDescription.new()

   if options.family then
      desc:set_family(options.family)
   else
      desc:set_family("serif") -- fallback
   end

   if options.weight then
      desc:set_weight(tonumber(options.weight))
   end

   if options.size then
      desc:set_size(options.size * pango.SCALE)
   end

   -- Add the font description to the attribute list
   pal:insert(pango.attr_font_desc_new(desc))

   if options.language then
      pal:insert(pango.attr_language_new(pango.Language.from_string(options.language)))
   end

   SU.debug("pango", "Created attribute list with font description:", desc:to_string())

   return pal
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
