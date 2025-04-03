local repeat_hyphen = require("languages.unicode-nodemaker")

local nodeMaker = pl.class(repeat_hyphen)
nodeMaker._name = "repeat-hyphen"

function nodeMaker:handleWordBreak (item)
   -- According to some language rules, when a break occurs at an explicit hyphen,
   -- the hyphen gets repeated at the beginning of the new line
   if item.text == "-" then
      self:addToken(item.text, item)
      self:makeToken()
      if self.lastnode ~= "discretionary" then
         coroutine.yield(SILE.types.node.discretionary({
            postbreak = SILE.shaper:createNnodes("-", self.options),
         }))
         self.lastnode = "discretionary"
      end
   else
      self:handleWordBreak(item)
   end
end

function nodeMaker:handleLineBreak (item, subtype)
   if self.lastnode == "discretionary" then
      -- Initial word boundary after a discretionary:
      -- Bypass it and just deal with the token.
      self:dealWith(item)
   else
      self:handleLineBreak(item, subtype)
   end
end

return nodeMaker
