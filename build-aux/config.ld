project = "SILE"
description = "The SILE Typesetter"
readme = "../README.md"
dir = "../lua-api-docs"
format = "discount"
file = {
   "../sile-lua",
   "../core/",
   "../types/",
   "../shapers/",
   "../outputters/",
   "../inputters/",
   "../classes/",
   "../packages/",
   "../typesetters/",
   "../fontmanagers/",
   "../linebreakers/",
   "../pagebuilders/",
   "../languages/",
}
merge = true
no_space_before_args = true
sort_modules = true
kind_names = { module = "Library" }
new_type("interfaces", "Interfaces", true)
new_type("types", "Types", true)
new_type("use", "Modules", true)
-- vim: ft=lua
