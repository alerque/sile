local lgi = require 'lgi'
local Pango = lgi.Pango
local PangoCairo = lgi.PangoCairo

local font_map = PangoCairo.FontMap.get_default()
local context = font_map:create_context()
context:set_language(Pango.Language.from_string("en-us"))
local font_desc = Pango.FontDescription.new()
font_desc:set_family("Gentium Plus")
font_desc:set_size(12 * Pango.SCALE)

local text = "text"
-- Create a layout instead of trying to shape directly
local layout = Pango.Layout.new(context)
layout:set_text(text)
layout:set_font_description(font_desc)

-- Get the layout's line and show glyph info
local line = layout:get_line(0)
local glyphs = line:get_glyphs()
print("Number of glyphs: " .. #glyphs)
