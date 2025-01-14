SILE = require("core.sile")
-- Using French below requires the shaper to be initialized
SILE.input.backend = "debug"
SILE.init()

describe("Hyphenation module", function ()
   local hyphenate = SILE.showHyphenationPoints

   SILE.call("language", { main = "fr" })

   describe("minWord with UTF8 in input text", function ()
      -- Trigger the initialization of the hyphenator
      -- so SILE._hyphenators["fr"] is created
      hyphenate("série", "fr")

      -- Current lefthyphenmin and righthyphenmin values
      -- for this test (whether changed or not for the language)
      SILE._hyphenators["fr"].leftmin = 2
      SILE._hyphenators["fr"].rightmin = 2

      it("should hyphenate words longer than minWord", function ()
         SILE._hyphenators["fr"].minWord = 5 -- (Default)
         assert.is.equal("sé-rie", hyphenate("série", "fr"))
         -- typos: ignore start
         assert.is.equal("Lé-gè-re-ment", hyphenate("Légèrement", "fr"))
         -- typos: ignore end
      end)

      it("should not hyphenate words shorter than minWord", function ()
         SILE._hyphenators["fr"].minWord = 6
         -- 5 characters but 6 bytes
         assert.is.equal("série", hyphenate("série", "fr"))
         SILE._hyphenators["fr"].minWord = 5 -- back to default
      end)
   end)

   describe("exceptions with UTF8 in input text", function ()
      SILE.call("hyphenator:add-exceptions", {}, { "légè-rement" })

      it("should hyphenate with exception rule", function ()
         assert.is.equal("légè-rement", hyphenate("légèrement", "fr"))
         assert.is.equal("Légè-rement", hyphenate("Légèrement", "fr"))
      end)
   end)
end)
