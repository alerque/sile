local lgi = require 'lgi'
local Pango = lgi.Pango
local PangoCairo = lgi.PangoCairo

-- Use a known-good font and create a context
local font_map = PangoCairo.FontMap.get_default()
local context = font_map:create_context()
local font_desc = Pango.FontDescription.from_string("DejaVu Sans 12")
local font = context:load_font(font_desc)
assert(font, "Font failed to load")

-- Text and length
local text = "text"
local bytes = text:len()

-- Build a fully populated Pango.Analysis
local analysis = Pango.Analysis {
  font = font,
  level = 0,
  gravity = Pango.Gravity.SOUTH,
  flags = 0,
  script = Pango.Script.LATIN
}

-- Shape
local glyphs = Pango.GlyphString.new()
Pango.shape(text, bytes, analysis, glyphs)

-- Results
print("Number of glyphs:", glyphs.num_glyphs)
for i = 0, glyphs.num_glyphs - 1 do
  local g = glyphs.glyphs[i]
  print(string.format("Glyph %d: index=%d, x_advance=%d", i, g.glyph, g.geometry.x_advance))
end
