--- SILE font type
-- @types font

local font = pl.class()
font.type = "font"

function font:_init (face, options)
   self.face = face
   self.options = options
end

return font
