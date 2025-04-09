-- This shaper package is deprecated and should only be used as an
-- example of how to create alternative shaper backends, in comparison
-- with the harfbuzz shaper.
local lgi = require("lgi")
require("string")
local pango = lgi.Pango
local pangocairo = lgi.PangoCairo
local fm = pangocairo.FontMap.get_default()
local pango_context = fm:create_context()
pango_context:set_round_glyph_positions(false)  -- We want exact positions
pango_context:set_language(pango.Language.get_default())
pango_context:set_base_dir(pango.Direction.LTR)  -- Default to left-to-right

local base = require("shapers.base")

local palcache = {}

local function _shape (text, item)
   local offset = item.offset
   local length = item.length
   local analysis = item.analysis

   local shaped_text = string.sub(text, 1 + offset, 1 + offset + length)

   -- Create a new GlyphString
   local pgs = pango.GlyphString.new()

   -- Ensure analysis and font are properly set
   if not (analysis and analysis.font) then
      local desc = pango.FontDescription.new()
      desc:set_family("serif")
      desc:set_absolute_size(12 * pango.SCALE)
      analysis = pango.Analysis.new()
      analysis.font = fm:load_font(pango_context, desc)
      analysis.level = 0  -- Set text direction (0 = LTR)
   end

   -- Shape with explicit length
   pango.shape(shaped_text, pango.AttrList.new(), analysis, pgs)

   -- Debugging output to verify shaping results
   SU.debug("pango", "Shaped result:", {
      text = shaped_text,
      glyphs = pgs.num_glyphs,
      has_font = analysis.font ~= nil,
      font_desc = analysis.font and analysis.font:describe():to_string() or "none"
   })

   -- Ensure the GlyphString has glyphs
   if pgs.num_glyphs == 0 then
      SU.warn("Pango shaping produced no glyphs for text: " .. shaped_text)
   end

   return pgs
end

local shaper = pl.class(base)
shaper._name = "pango"

-- TODO: refactor so method accepts self
function shaper.getFace (options)
   -- Create a unique key for caching
   local key = options.family .. ":" .. options.size .. ":" .. (options.weight or "")
   if palcache[key] then return palcache[key] end

   local face = SILE.fontManager:face(options)
   if not face then
      SU.error("Couldn't find face '" .. options.family .. "'")
   end

   -- Create font description
   local desc = pango.FontDescription.new()
   desc:set_family(face.family)
   desc:set_absolute_size(options.size * pango.SCALE)
   if options.weight then
      desc:set_weight(tonumber(options.weight))
   end
   if options.style then
      desc:set_style(options.style:lower() == "italic" and pango.Style.ITALIC or pango.Style.NORMAL)
   end

   -- Create a new context for this font
   local context = pango.Context.new()
   context:set_font_description(desc)

   -- Create attribute list
   local pal = pango.AttrList.new()
   pal:insert(pango.attr_font_desc_new(desc))

   if options.language then
      pal:insert(pango.attr_language_new(pango.Language.from_string(options.language)))
   end

   palcache[key] = pal
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
