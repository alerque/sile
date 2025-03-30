local unicode = require("languages.unicode")

local language = pl.class(unicode)
language._name = "la"

-- local hyphens = require("languages.la.hyphens-tex")
-- SILE.hyphenator.languages["la"] = hyphens

return language
