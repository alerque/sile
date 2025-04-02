local unicode = require("languages.unicode")

local language = pl.class(base)
language._name = "kn"

function language:declareSettings (typesetter)
   -- TODO get this *unset* when switching to other languages
   SILE.settings:set("font.script", "Knda")
end

return language
