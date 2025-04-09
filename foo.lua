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
local item = Pango.Item.new()
item.offset = 0
item.length = #text
item.analysis = {
    font = context:load_font(font_desc),
    level = 0,
}
local analysis = item.analysis
local pgs = Pango.GlyphString.new()

Pango.shape(text, #text, analysis, pgs)
print("Number of glyphs: " .. pgs.num_glyphs)
