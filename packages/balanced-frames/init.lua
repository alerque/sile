local base = require("packages.base")

local package = pl.class(base)
package._name = "balanced-frames"

local BALANCE_PENALTY = -17777

local unbalanced_buildPage

local function buildPage (typesetter, independent)
   local frame = typesetter.frame
   if not (frame.balanced == true) then
      return unbalanced_buildPage(typesetter, independent)
   end

   local colCount = 0
   local target = SILE.types.length()
   while frame and frame.balanced == true do
      target = target + frame:height()
      colCount = colCount + 1
      if frame.next then
         frame = SILE.getFrame(frame.next)
      else
         break
      end
   end

   -- Really, try and avoid doing anything, where possible.
   if colCount == 1 then
      return unbalanced_buildPage(typesetter, independent)
   end
   -- If the total amount of stuff on the output list is greater then the total
   -- of frame space on the page, and there are no magic requests to balance the
   -- columns, then we have a full page. Just send it out normally.
   local q = typesetter.state.outputQueue
   local totalHeight = SILE.types.length()
   local mustBalance = 0
   for i = 1, #q do
      totalHeight = totalHeight + q[i].height + q[i].depth
      if q[i].is_penalty and q[i].penalty <= BALANCE_PENALTY then
         mustBalance = i
         break
      end
   end
   if totalHeight.length > target.length and mustBalance == 0 and not independent then
      return unbalanced_buildPage(typesetter, independent)
   end

   -- Have we been explicitly asked to find a pagebreak at this point?
   -- If not, don't bother
   if mustBalance == 0 and not independent then
      return false
   end
   SU.debug("balancer", "Balancing", totalHeight, "of material over", colCount, "frames (total of", target, ")")
   SU.debug("balancer", "Must balance because mustBalance =", mustBalance, "and independent =", independent)
   -- OK. Now we have to balance the frames. We are going to cheat and
   -- adjust the height of each frame to be an appropriate fraction of
   -- the content height
   frame = typesetter.frame
   SU.debug("balancer", "Each column is now", totalHeight.length / colCount)
   while frame and frame.balanced == true do
      frame:relax("bottom")
      frame:constrain("height", totalHeight.length / colCount)
      if frame.next then
         frame = SILE.getFrame(frame.next)
      else
         break
      end
   end
   typesetter.state.lastPenalty = 0
   local oldPageBuilder = typesetter.pagebuilder
   typesetter.pagebuilder = SILE.pagebuilders.default()
   while typesetter.frame and typesetter.frame.balanced do
      unbalanced_buildPage(typesetter, true)
      if typesetter.frame.next and SILE.getFrame(typesetter.frame.next).balanced == true then
         typesetter:initFrame(SILE.getFrame(typesetter.frame.next))
         typesetter:runHooks("newframe")
      else
         break -- Break early, because when we return
      end
   end
   typesetter.pagebuilder = oldPageBuilder
   SU.debug("balancer", "Finished this balance, frame id is now", typesetter.frame)
   -- SILE.typesetter:debugState()
   -- We're done.
   return true
end

function package:_init (options)
   base._init(self, options)
   self.class:registerPostinit(function (_)
      if not unbalanced_buildPage then
         unbalanced_buildPage = SILE.typesetter.buildPage
         SILE.typesetter.buildPage = buildPage
         SILE.typesetters.base.buildPage = buildPage
      end
   end)
end

function package:registerCommands ()
   self.commands:register("balancecolumns", function (_, _)
      SILE.typesetter:leaveHmode()
      SILE.call("penalty", { penalty = BALANCE_PENALTY })
   end)
end

package.documentation = [[
\begin{document}
This package attempts to ensure that the main content frames on a page are balanced; that is, that they have the same height.
In your frame definitions for the columns, you will need to ensure that they have the parameter \autodoc:parameter{balanced} set to \code{true}.
See the example in \code{tests/balanced.sil}.

The current algorithm does not work particularly well, and a better solution to the column problem is being developed.
\end{document}
]]

return package
