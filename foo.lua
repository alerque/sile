local lgi = require("lgi")
local D = require("pl.pretty").debug

function glyphstring ()
   local Pango = lgi.Pango
   local pal = Pango.AttrList.new()
   pal:insert(Pango.Attribute.language_new(Pango.Language.from_string("en")))
   pal:insert(Pango.Attribute.family_new("Gentium Plus 12"))
   pal:insert(Pango.Attribute.size_new(12))

   local fm = lgi.PangoCairo.FontMap.get_default()
   local pango_context = Pango.FontMap.create_context(fm)
   pango_context:set_language(Pango.Language.from_string("en"))

   local s = "foo bar"
   local items = Pango.itemize(pango_context, s, 0, string.len(s), pal, nil)

   for i in pairs(items) do
      local offset = items[i].offset
      local length = items[i].length
      local analysis = items[i].analysis
      local pgs = Pango.GlyphString()
      Pango.shape(string.sub(s, 1 + offset), length, analysis, pgs)
      local glyphs = pgs.glyphs
      D(type(glyphs) == "table", #glyphs > 0, Pango.GlyphInfo:is_type_of(glyphs[1]))
      D(glyphs)
   end
end

glyphstring()
