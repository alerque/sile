SILE = require("core.sile")
SILE.backend = "debug"
SILE.init()

local doc = [[
\begin{document}
foo
\begin{script}
SILE.processString("\\em{qiz} \\lua{print(6)} \\xml{<em>bob<lua>print(7);SU.error('bob')</lua></em>}", "sil")
\end{script}
\end{document}
]]

describe("TraceStack", function ()

  it("should locate errors in nested languages", function ()
    local process = function () SILE.processString(doc, "sil") end
    assert.has_error(process, "bob")
  end)

end)
