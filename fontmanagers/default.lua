local base = require("fontmanagers.base")

local fontconfig = require("fontmanagers.fontconfig")
local macfonts = require("fontmanagers.macfonts")

local fontmanager = pl.class(base)
fontmanager._name = "default"

function fontmanager:_init ()
   base._init(self)
   local havefontconfig, fc = pcall(fontconfig)
   if havefontconfig then
      self.fontconfig = fc
   end
   local havemacfonts, mf = pcall(macfonts)
   if havemacfonts then
      self.macfonts = mf
   end
end

function fontmanager:load (options)
   if self.macfonts then
      SU.debug("fontmanager", "Checking via macfonts")
      local status, face = pcall(self.macfonts.face, self.macfonts, options)
      if status and face and face.filename then
         SU.debug("fontmanager", "Found via macfonts, returning face")
         return SILE.types.font(face)
      end
   end
   if self.fontconfig then
      SU.debug("fontmanager", "Checking via fontconfig")
      local status, face = pcall(self.fontconfig.face, self.fontconfig, options)
      if status and face and face.filename then
         SU.debug("fontmanager", "Found via fontconfig, returning face")
         return SILE.types.font(face)
      end
   end
   SU.debug("fontmanager", "Unable to find font via any manager")
end

return fontmanager
