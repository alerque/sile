local lgi = require("lgi")
local Pango = lgi.Pango
local Cairo = lgi.cairo

-- Create a dummy Cairo surface/context (needed for Pango layout)
local surface = Cairo.ImageSurface.create('ARGB32', 500, 100)
local cr = Cairo.Context(surface)

-- Create a Pango layout using the Cairo context
local layout = Pango.cairo_create_layout(cr)

-- Set text and font
layout:set_text("Hello, 世界", -1)
local font_desc = Pango.FontDescription.from_string("Sans 20")
layout:set_font_description(font_desc)

-- Optionally set alignment, width, etc.
-- layout:set_width(Pango.SCALE * 400)
-- layout:set_alignment(Pango.Alignment.CENTER)

-- Get the layout's size (in Pango units, divide by Pango.SCALE for pixels)
local width, height = layout:get_size()
print(string.format("Text size: %d x %d pixels", width / Pango.SCALE, height / Pango.SCALE))

-- Render the layout (optional if you just need shaping info)
Pango.cairo_show_layout(cr, layout)
surface:write_to_png("output.png")  -- Save the rendered image (optional)

-- Access shaped information (e.g., glyphs, runs)
local iter = layout:get_iter()
repeat
    local run = iter:get_run()
    if run then
        local glyph_items = run:get_glyphs()
        for i, glyph in ipairs(glyph_items.glyphs) do
            print(string.format("Glyph index: %d, geometry: x=%d, y=%d", glyph.glyph, glyph.geometry.x_offset, glyph.geometry.y_offset))
        end
    end
until not iter:next_run()
