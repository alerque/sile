local lgi = require 'lgi'
local Pango = lgi.Pango
local PangoCairo = lgi.PangoCairo

local font_map = PangoCairo.FontMap.get_default()
local context = font_map:create_context()
context:set_language(Pango.Language.from_string("en-us"))

local font_desc = Pango.FontDescription.new()
font_desc:set_family("Serif")
font_desc:set_size(12 * Pango.SCALE)

local text = "text"

-- Create a valid analysis object
local analysis = Pango.Analysis()
analysis.font = context:load_font(font_desc)
analysis.level = 0

local pgs = Pango.GlyphString.new()
Pango.shape(text, #text, analysis, pgs)

print("Number of glyphs: " .. pgs.num_glyphs)

for i = 0, pgs.num_glyphs - 1 do
    local glyph_info = pgs.glyphs[i]
    print(string.format("Glyph %d: index=%d, x_advance=%d, y_advance=%d", i, glyph_info.glyph, glyph_info.geometry.x_advance, glyph_info.geometry.y_advance))
end
