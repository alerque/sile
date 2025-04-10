local lgi = require 'lgi'
local Pango = lgi.Pango
local PangoCairo = lgi.PangoCairo

-- Create a font map and context
local font_map = PangoCairo.FontMap.get_default()
local context = font_map:create_context()

-- Set up font description
local font_desc = Pango.FontDescription.from_string("Serif 12")
local font = context:load_font(font_desc)

print("Loaded font: ", font)

-- Sanity check that font loaded
assert(font, "Failed to load font")

-- Create a proper Analysis object
local analysis = Pango.Analysis()
analysis.font = font
analysis.level = 0

-- Input text
local text = "text"

-- Create a glyph string
local glyphs = Pango.GlyphString.new()

-- Perform shaping
Pango.shape(text, #text, analysis, glyphs)

-- Output shaped data
print("Number of glyphs: " .. glyphs.num_glyphs)

for i = 0, glyphs.num_glyphs - 1 do
    local g = glyphs.glyphs[i]
    print(string.format("Glyph %d: index=%d, x_advance=%d", i, g.glyph, g.geometry.x_advance))
end
