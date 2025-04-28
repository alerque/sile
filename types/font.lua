--- SILE font type
-- @types font

local font = pl.class()
font.type = "font"

function font:_init (face, options)
   self.face = face
   self.options = options
end

function font:is_pango ()
   return type(self.face) == userdata and type(face.insert) == "function"
end

return font
