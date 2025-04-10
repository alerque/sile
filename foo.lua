local lgi = require 'lgi'
local Pango = lgi.Pango
local PangoCairo = lgi.PangoCairo

-- Create a font map and context
local font_map = PangoCairo.FontMap.get_default()
local context = font_map:create_context()

-- Set up font and language
local font_desc = Pango.FontDescription.from_string("DejaVu Sans 12")
context:set_font_description(font_desc)
context:set_language(Pango.Language.from_string("en"))

-- Input text
local text = "text"
print("Text: ", text, "Length: ", #text)

-- Itemize the text
local attr_list = Pango.AttrList.new()
local items = Pango.itemize(context, text, 0, #text, attr_list, nil)
print("Number of items: ", #items)

-- Shape each item
local total_glyphs = 0
for i, item in ipairs(items) do
    print("Item ", i, " offset: ", item.offset, " length: ", item.length)
    -- Adjust for Lua's 1-based indexing vs Pango's 0-based offsets
    local start = item.offset + 1
    local end_pos = item.offset + item.length
    local subtext = text:sub(start, end_pos)
    print("Substring: '", subtext, "' Length: ", #subtext)
    
    -- Get the font from the analysis structure
    local font = item.analysis.font
    print("Analysis font: ", font)
    
    -- Create a new glyph string for each item
    local glyphs = Pango.GlyphString.new()
    
    -- Make sure we have a valid font before shaping
    if font then
        -- Use the proper API based on Pango version
        if Pango.shape_item then
            -- Newer Pango versions
            Pango.shape_item(item, subtext, glyphs)
        else
            -- Direct shape call - ensure parameters are correct for LGI
            -- Pass text directly rather than substring to avoid encoding issues
            Pango.shape(subtext, -1, item.analysis, glyphs)
        end
    else
        print("Warning: No font in analysis, cannot shape")
    end

    print("Glyphs for item ", i, ": ", glyphs.num_glyphs)
    
    -- Display glyph info
    if glyphs.num_glyphs > 0 then
        for g = 0, glyphs.num_glyphs - 1 do
            local glyph_info = glyphs:get_glyph_info(g)
            print(string.format("  Glyph %d: glyph=%d char=%d", 
                  g, glyph_info.glyph, glyph_info.chars))
        end
    end
    
    total_glyphs = total_glyphs + glyphs.num_glyphs
end

-- Check results
print("Total glyphs: ", total_glyphs)