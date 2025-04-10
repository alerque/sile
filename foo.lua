local lgi = require 'lgi'
local Pango = lgi.Pango
local PangoCairo = lgi.PangoCairo

-- Create a font map and context
local font_map = PangoCairo.FontMap.get_default()
local context = font_map:create_context()

-- Set up font
local font_desc = Pango.FontDescription.from_string("Serif 12")
context:set_font_description(font_desc)
context:set_language(Pango.Language.from_string("en"))

-- Input text
local text = "text"

-- Itemize the text manually
local attr_list = Pango.AttrList.new()
local items = Pango.itemize(context, text, 0, #text, attr_list, nil)
print("Number of items: ", #items)

-- Shape each item
local glyphs = Pango.GlyphString.new()
for i, item in ipairs(items) do
    print("Item ", i, " offset: ", item.offset, " length: ", item.length)
    Pango.shape(text:sub(item.offset + 1, item.offset + item.length), item.length, item.analysis, glyphs)
    print("Glyphs for item ", i, ": ", glyphs.num_glyphs)
end

-- Check results
print("Total glyphs: ", glyphs.num_glyphs)
