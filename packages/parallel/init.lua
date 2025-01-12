local base = require("packages.base")

local package = pl.class(base)
package._name = "parallel"

-- Typesetter pool for managing typesetters for different frames (e.g., left and right frames).
local typesetterPool, footnotePool = {}, {}

-- Make sure you have ftn_left and ftn_right frames setup in your document class
local footnotes = { ftn_left = {}, ftn_right = {} }

-- Cache for footnote heights
local footnoteHeightCache = {}

-- Stores layout calculations for each frame, such as height, marking and overflow tracking.
local calculations = {}

-- Specifies the order of frames for synchronizing and page-breaking logic.
local folioOrder = {}

-- A null typesetter used as a placeholder. This typesetter doesn't output any content.
-- Its purpose is to make the transtion between frames easier and trouble free.
local nulTypesetter = pl.class(SILE.typesetters.base)
nulTypesetter.outputLinesToPage = function () end -- Override to suppress output

-- Utility function: Iterate through all typesetters and apply a callback function to each.
local allTypesetters = function (callback)
   local oldtypesetter = SILE.typesetter -- Save the current typesetter
   for frame, typesetter in pairs(typesetterPool) do
      SILE.typesetter = typesetter -- Switch to the current frame's typesetter
      callback(frame, typesetter) -- Execute the callback
   end
   SILE.typesetter = oldtypesetter -- Restore the original typesetter
end

-- Utility function: Calculate the height of new material for a given frame.
local calculateFrameHeight = function (frame, typesetter)
   local height = calculations[frame].cumulativeHeight or SILE.types.length()
   -- typesetter.state.outputQueue now holds actual content reflecting the real layout of lines.
   -- Therefore, we can calculate the height of new material by adding the height of each line
   -- in the queue.
   for i = calculations[frame].mark + 1, #typesetter.state.outputQueue do
      local lineHeight = typesetter.state.outputQueue[i].height + typesetter.state.outputQueue[i].depth
      height = height + lineHeight
   end
   -- calculations[frame].cumulativeHeight = height -- Store updated cumulative height
   return height
end

-- Calculate line height of a sample text
local calculateLineHeight = function (sampleText)
   local glyphs = SILE.shaper:shapeToken(sampleText, SILE.font.loadDefaults({}))
   local baselineSkip = SILE.settings:get("document.baselineskip").height
   -- Use a sample text containing two characters, one with ascender and one with descender
   -- baselineskip should be accounted for
   return glyphs[1].height + glyphs[2].depth + baselineSkip:tonumber()
end

-- Create dummy content to fill up the overflowed frames.
local createDummyContent = function (height, frame, offset)
   -- Get the typesetter for the frame
   local typesetter = typesetterPool[frame]

   -- Calculate precise line height by typesetting a sample line
   -- local lineHeight = calculateLineHeight("hg")

   -- SU.debug(package._name, "Precise lineHeight after simulation = ", lineHeight)

   -- If lineHeight could not be calculated, fall back to baselineSkip and lineSkip of the document
   if not lineHeight then
      local baselineSkip = SILE.settings:get("document.baselineskip").height or SILE.types.length({ length = 0 })
      local lineSkip = SILE.settings:get("document.lineskip").height or SILE.types.length({ length = 0 })
      lineHeight = baselineSkip:tonumber() + lineSkip:tonumber()
      -- SU.debug(package._name, "Precise lineHeight based on document.baselineskip = ", lineHeight)
   end

   -- Calculate the number of lines needed
   local numLines = math.floor(height:tonumber() / lineHeight)

   -- Validate offset
   offset = offset or 0
   if offset >= numLines then
      SU.warn("Offset is larger than the number of lines available; no dummy content will be generated.")
      return
   end

   -- Add dummy content to fill the frame
   SILE.call("color", { color = "white" }, function ()
      typesetter:typeset("sile")
      for i = 1, numLines - offset do
         -- Add dummy content and a line break
         SILE.call("break")
         typesetter:typeset("sile")
      end
   end)
end

local balanceFramesWithDummyContent = function (offset)
   local frameHeights = {}
   local maxHeight = SILE.types.length(0)

   -- Step 1: Measure frame heights and determine the maximum height
   allTypesetters(function (frame, typesetter)
      local height = calculateFrameHeight(frame, typesetter)
      frameHeights[frame] = height
      if height > maxHeight then
         maxHeight = height
      end
   end)

   -- Step 2: Add dummy content to balance frames
   allTypesetters(function (frame, typesetter)
      local heightDifference = maxHeight - frameHeights[frame]
      if heightDifference:tonumber() > 0 then
         SILE.typesetter = typesetter
         createDummyContent(SILE.types.length(heightDifference), frame, offset or 0)
      end
   end)

   -- Optional: Log balancing results
   SU.debug(package._name, "Balanced frames to height: ", maxHeight)
end

-- Balances the height of content across frames by adding glue to the shorter frame.
local addBalancingGlue = function (height)
   allTypesetters(function (frame, typesetter)
      calculations[frame].heightOfNewMaterial = calculateFrameHeight(frame, typesetter)
      local glue = height - calculations[frame].heightOfNewMaterial

      if glue:tonumber() > 0 then
         table.insert(typesetter.state.outputQueue, SILE.types.node.vglue({ height = glue }))
         SU.debug(package._name, "Already added balancing glue of", glue, " to bottom of frame", frame)
      end
      -- We would not need to set the marking here, the `\sync` command will take care of that
      -- calculations[frame].mark = #typesetter.state.outputQueue
   end)
end

-- Adds a flexible glue (parskip) to the bottom of each frame
-- This is decoupled from addBalancingGlue calculations, serving a simple purpose.
local addParskipToFrames = function (parskipHeight)
   allTypesetters(function (_, typesetter)
      table.insert(typesetter.state.outputQueue, SILE.types.node.vglue({ height = parskipHeight }))
   end)
end

-- Measure the width of a string used in footnote marker
local measureStringWidth = function (str)
   -- Shape the string in the current font context
   local shapedText = SILE.shaper:shapeToken(str, SILE.font.loadDefaults({}))

   local totalWidth = 0
   for _, glyph in ipairs(shapedText) do
      totalWidth = totalWidth + glyph.width
   end
   return totalWidth
end

-- Create a unique id for each footnote
local function generateFootnoteId (frame, note)
   return frame .. ":" .. note.marker
end

local function getFootnoteHeight (frame, note, typesetter)
   local noteId = generateFootnoteId(frame, note)

   -- Simulate typesetting to calculate height
   local noteQueue = {}
   typesetter:pushState()
   -- Redirect the output queue to the noteQueue
   typesetter.state.outputQueue = noteQueue
   SILE.call("parallel_footnote:constructor", { marker = note.marker }, note.content)
   typesetter:popState()

   -- Measure the height of the simulated queue
   local noteHeight = 0
   for _, node in ipairs(noteQueue) do
      noteHeight = noteHeight + node.height:absolute():tonumber() + node.depth:absolute():tonumber()
   end

   -- Cache the calculated height
   footnoteHeightCache[noteId] = noteHeight
   -- Return the calculated height and the simulated noteQueue for footnote content
   -- the noteQueue will be used later to for spliting if needed
   return noteHeight, noteQueue
end

local typesetFootnotes = function ()
   for frame, notes in pairs(footnotes) do
      if notes and #notes > 0 then
         SU.debug(package._name, "Processing footnotes for frame: " .. frame)

         local typesetter = footnotePool[frame]
         typesetter:initFrame(typesetter.frame)
         SILE.typesetter = typesetter

         -- Add a rule above the footnotes
         SILE.call("parallel_footnote:rule")

         local nextPageNotes = {}

         SILE.settings:temporarily(function ()
            -- SILE.settings:set("font.size", SILE.settings:get("font.size") * 0.85)
            SILE.call("break") -- To prevent the firt footnote being streched across the frame

            local targetHeight = typesetter:getTargetLength():tonumber()
            local currentHeight = 0
            local baselineSkip = SILE.settings:get("document.baselineskip").height:tonumber() * 0.30

            for i, note in ipairs(notes) do
               -- Get the cached or calculated height and simulated noteQueue
               local noteHeight, noteQueue = getFootnoteHeight(frame, note, typesetter)

               -- Adjust for baseline skip
               if i > 1 then
                  noteHeight = noteHeight + baselineSkip
               end

               if currentHeight + noteHeight <= targetHeight then
                  -- Add baseline skip before adding the note (except the first note)
                  if i > 1 then
                     table.insert(typesetter.state.outputQueue, SILE.types.node.vglue(SILE.types.length(baselineSkip)))
                  end

                  -- Note fits entirely
                  currentHeight = currentHeight + noteHeight
                  for _, node in ipairs(noteQueue) do
                     table.insert(typesetter.state.outputQueue, node)
                  end
               else
                  -- Note needs to be split
                  local fittedQueue = {}
                  local remainingQueue = {}
                  local fittedHeight = 0

                  for _, node in ipairs(noteQueue) do
                     local nodeHeight = node.height:absolute():tonumber() + node.depth:absolute():tonumber()
                     if fittedHeight + nodeHeight <= (targetHeight - currentHeight) then
                        table.insert(fittedQueue, node)
                        fittedHeight = fittedHeight + nodeHeight
                     else
                        -- Whatever does not fit is sent to the remaining queue
                        table.insert(remainingQueue, node)
                     end
                  end

                  -- Flush noteQueue from the memory for optimization
                  noteQueue = nil

                  -- Add fitted part to the current frame
                  if #typesetter.state.outputQueue > 0 then
                     table.insert(typesetter.state.outputQueue, SILE.types.node.vglue(SILE.types.length(baselineSkip)))
                  end

                  currentHeight = currentHeight + fittedHeight
                  for _, node in ipairs(fittedQueue) do
                     table.insert(typesetter.state.outputQueue, node)
                  end

                  -- Typeset the fitted part to the current frame
                  typesetter:outputLinesToPage(typesetter.state.outputQueue)

                  -- Reset output queue and move on
                  typesetter.state.outputQueue = {}

                  -- Create a new "split" note and add notes to the next page
                  if #remainingQueue > 0 then
                     local contentFunc = function ()
                        for _, node in ipairs(remainingQueue) do
                           table.insert(SILE.typesetter.state.outputQueue, node)
                        end
                     end
                     table.insert(nextPageNotes, {
                        -- Suppress the footnote marker for the overflowed note
                        -- number = "",
                        marker = "",
                        content = contentFunc,
                     })
                  end
               end
            end

            -- Output any remaining content
            if typesetter.state.outputQueue and #typesetter.state.outputQueue > 0 then
               typesetter:outputLinesToPage(typesetter.state.outputQueue)
            else
               SU.warn("No content to output for frame: " .. frame)
            end

            -- Add remaining notes to the next page
            footnotes[frame] = nextPageNotes

            -- Reset output queue after typesetting the remaining footnote content
            typesetter.state.outputQueue = {}
         end)
      else
         SU.debug(package._name, "No footnotes to process for frame: " .. frame)
      end
   end
end

-- Handles page-breaking logic for parallel frames.
local parallelPagebreak = function ()
   for _, thisPageFrames in ipairs(folioOrder) do
      local hasOverflow = false
      local overflowContent = {}

      -- Process each frame for overflow content
      allTypesetters(function (frame, typesetter)
         typesetter:initFrame(typesetter.frame)
         local thispage = {}
         local linesToFit = typesetter.state.outputQueue
         local targetLength = typesetter:getTargetLength():tonumber()
         local currentHeight = 0

         while
            #linesToFit > 0
            and currentHeight + (linesToFit[1].height:tonumber() + linesToFit[1].depth:tonumber()) <= targetLength
         do
            local line = table.remove(linesToFit, 1)
            currentHeight = currentHeight + (line.height:tonumber() + line.depth:tonumber())
            table.insert(thispage, line)
         end

         if #linesToFit > 0 then
            hasOverflow = true
            overflowContent[frame] = linesToFit
            typesetter.state.outputQueue = {}
         else
            overflowContent[frame] = {}
         end

         typesetter:outputLinesToPage(thispage)
      end)

      -- Process footnotes before page break
      typesetFootnotes()

      -- End the current page
      SILE.documentState.documentClass:endPage()

      if hasOverflow then
         -- Start a new page
         SILE.documentState.documentClass:newPage()

         -- Restore overflow content to the frames
         for frame, overflowLines in pairs(overflowContent) do
            local typesetter = typesetterPool[frame]
            for _, line in ipairs(overflowLines) do
               table.insert(typesetter.state.outputQueue, line)
            end
         end

         -- Rebalance frames
         balanceFramesWithDummyContent()
      end
   end

   -- Ensure all the first pair of frames on the new page are synchronized
   SILE.call("sync")
end

-- Initialization function for the package.
function package:_init (options)
   base._init(self, options)

   -- Load necessary packages
   self:loadPackage("rebox") -- for footnote:rule
   self:loadPackage("rules") -- for footnote:rule
   self:loadPackage("counters") -- for footnote counting
   self:loadPackage("raiselower") -- for footnote superscript mark
   -- Load the `resilient.footnotes` package for the footenot:mark style.
   -- self:loadPackage("resilient.footnotes")

   -- Initialize the null typesetter.
   SILE.typesetter = nulTypesetter(SILE.getFrame("page"))

   -- Ensure the `frames` option is provided.
   if type(options.frames) ~= "table" or type(options.ftn_frames) ~= "table" then
      SU.error("Package parallel must be initialized with a set of appropriately named frames")
   end

   -- Set up typesetters for each frame.
   for frame, typesetter in pairs(options.frames) do
      typesetterPool[frame] = SILE.typesetters.base(SILE.getFrame(typesetter))
      typesetterPool[frame].id = typesetter
      typesetterPool[frame].buildPage = function () end -- Disable auto page-building

      -- Register commands (e.g., \left, \right) for directing content to frames.
      local fontcommand = frame .. ":font"
      self:registerCommand(frame, function (_, _)
         SILE.typesetter = typesetterPool[frame]
         SILE.call(fontcommand)
      end)

      -- Define default font commands for frames if not already defined.
      if not SILE.Commands[fontcommand] then
         self:registerCommand(fontcommand, function (_, _) end)
      end
   end

   -- Set up typesetters for each footnote frame.
   for frame, typesetter in pairs(options.ftn_frames) do
      footnotePool[frame] = SILE.typesetters.base(SILE.getFrame(typesetter))
      footnotePool[frame].id = typesetter
      -- You should not disable the auto page-building here, otherwise you can't typeset
      -- any footnotes on the last page of your document.
   end

   -- Configure the order of frames for the folio (page layout).
   if not options.folios then
      folioOrder = { {} }
      for frame, _ in pl.tablex.sort(options.frames) do
         table.insert(folioOrder[1], frame)
      end
   else
      folioOrder = options.folios
   end

   -- Customize the `newPage` method to synchronize frames.
   -- Ensure that each new page starts clean but balanced
   self.class.newPage = function (self_)
      self.class._base.newPage(self_)

      -- Reset calculations
      allTypesetters(function (frame, _)
         calculations[frame] = { mark = 0 }
      end)

      -- Align and balance frames
      SILE.call("sync")
   end

   -- Initialize calculations for each frame.
   allTypesetters(function (frame, _)
      calculations[frame] = { mark = 0 }
   end)

   -- Override the `finish` method to handle parallel page-breaking.
   local oldfinish = self.class.finish
   self.class.finish = function (self_)
      parallelPagebreak()
      oldfinish(self_)
   end
end

-- Registers commands for the package.
function package:registerCommands ()
   -- shortcut for \parskip
   self:registerCommand("parskip", function (options, _)
      local height = options.height or "12pt plus 3pt minus 1pt"
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushExplicitVglue(SILE.types.length(height))
   end)

   self:registerCommand("sync", function (_, _)
      local anybreak = false
      local maxheight = SILE.types.length()

      -- Check for potential page breaks.
      allTypesetters(function (_, typesetter)
         typesetter:leaveHmode(true)
         local lines = pl.tablex.copy(typesetter.state.outputQueue)
         if SILE.pagebuilder:findBestBreak({ vboxlist = lines, target = typesetter:getTargetLength() }) then
            anybreak = true
         end
      end)

      -- Perform a page break if necessary.
      if anybreak then
         parallelPagebreak()
         return
      end

      -- Calculate the height of new material for balancing.
      allTypesetters(function (frame, typesetter)
         calculations[frame].heightOfNewMaterial = calculateFrameHeight(frame, typesetter)
         if calculations[frame].heightOfNewMaterial > maxheight then
            maxheight = calculations[frame].heightOfNewMaterial
            SU.debug(package._name, "Value of maxheight after balancing for frame ", frame, ": ", maxheight)
         end
      end)

      -- Add balancing glue
      addBalancingGlue(maxheight)

      -- Check if parskip is effectively nil
      local parskip = SILE.settings:get("document.parskip")
      -- SU.debug("parallel", "parsing parskip", parskip.length, parskip.stretch, parskip.shrink)

      if not parskip.length then
         -- Insert flexible glue to manage space between two successive pairs of frames separated by the  \sync command
         -- Add parskip to the bottom of both frames
         addParskipToFrames(SILE.types.length("12pt plus 3pt minus 1pt"))
      else
         -- Add the value of parskip set by user
         addParskipToFrames(parskip)
      end
   end)

   self:registerCommand("smaller", function (_, content)
      SILE.settings:temporarily(function ()
         local currentSize = SILE.settings:get("font.size")
         SILE.settings:set("font.size", currentSize * 0.75) -- Scale down to 75%
         SILE.settings:set("font.weight", 800)
         SILE.process(content)
      end)
   end)

   self:registerCommand("footnoteNumber", function (options, content)
      local height = options.height or "0.3em" -- Default height for superscripts
      SILE.call("raise", { height = height }, function ()
         SILE.call("smaller", {}, function ()
            SILE.process(content)
         end)
      end)
   end)

   -- Stolen from `resilient.footnotes` package
   self:registerCommand("parallel_footnote:rule", function (options, _)
      local width = SU.cast("measurement", options.width or "20%fw") -- "Usually 1/5 of the text block"
      local beforeskipamount = SU.cast("vglue", options.beforeskipamount or "1ex")
      local afterskipamount = SU.cast("vglue", options.afterskipamount or "1ex")
      local thickness = SU.cast("measurement", options.thickness or "0.5pt")
      SILE.call("noindent")
      -- SILE.typesetter:pushExplicitVglue(beforeskipamount)
      SILE.call("rebox", {}, function ()
         SILE.call("hrule", { width = width, height = thickness })
      end)
      SILE.typesetter:leaveHmode()
      SILE.typesetter:pushExplicitVglue(afterskipamount)
   end, "Small helper command to set a footnote rule.")

   self:registerCommand("parallel_footnote:constructor", function (options, content)
      local markerText = options.marker or "?" -- Default marker if none provided

      SILE.settings:temporarily(function ()
         -- Set font footnotes, 80% of current font size
         SILE.settings:set("font.size", SILE.settings:get("font.size") * 0.80)

         -- Measure the marker width
         local markerWidth = measureStringWidth(markerText)

         -- Set hanging indentation
         local hangIndent = SILE.types.length("14.4pt"):absolute()
         SILE.settings:set("current.hangAfter", 1) -- Indent subsequent lines
         SILE.settings:set("current.hangIndent", hangIndent)

         -- Calculate the gap after the marker
         local markerGap = hangIndent - markerWidth

         -- Debugging
         -- SU.debug(package._name, "Hanging Indent: ",  hangIndent)
         -- SU.debug(package._name, "Marker Width: ", markerWidth)
         -- SU.debug(package._name, "Marker Gap: ", markerGap)

         -- Typeset the marker
         SILE.typesetter:typeset(markerText)

         -- Add spacing after the marker for alignment
         SILE.call("kern", { width = markerGap })

         -- Process the footnote content
         SILE.process(content)

         -- End the paragraph
         SILE.call("par")
      end)
   end)

   self:registerCommand("parallel_footnote", function (options, content)
      local currentFrame = SILE.typesetter.frame.id
      local targetFrame = currentFrame == "a" and "ftn_left" or "ftn_right"

      -- Increment or retrieve the footnote counter for the target frame
      local footnoteNumber
      if not options.mark then
         SILE.call("increment-counter", { id = targetFrame })
         footnoteNumber = self.class.packages.counters:formatCounter(SILE.scratch.counters[targetFrame])
      else
         footnoteNumber = options.mark
      end

      -- Add the footnote marker to the text
      SILE.call("footnoteNumber", {}, function ()
         SILE.typesetter:typeset(footnoteNumber)
      end)

      -- Add the footnote content to the frame's list
      if footnotes[targetFrame] then
         table.insert(footnotes[targetFrame], {
            -- number = footnoteNumber,
            marker = tostring(footnoteNumber) .. ".",
            content = content,
         })
      end
   end)
end

package.documentation = [[
\begin{document}
The \autodoc:package{parallel} package provides a mechanism for typesetting diglot or other parallel documents. When used by a class such as \code{classes/diglot.lua}, it registers a command for each parallel frame, allowing users to select which frame to typeset into.

The package defines the \autodoc:command{\sync} command, which adds vertical spacing to the bottom of each frame to ensure that the \em{next} set of text is horizontally aligned. It also supports independent footnote flows and counters for each frame. Footnotes can be typeset using \autodoc:command{\parallel_footnote}, with styles adopted from the \code{resilient.footnotes} package. Note that \code{document.parskip} is not supported due to manual manipulation of \code{typesetter.state.outputQueue}. Therefore, to start a new paragraph within a frame, users must manually use the \autodoc:command{\parskip} command.

This package is under development and not yet fully mature. Testing has shown that it works best with a font size of 12pt from the \strong{Gentium Plus} family. Custom settings for \code{document.parskip}, \code{document.baselineskip}, or using different font sizes between frames may disrupt frame alignment, making precise alignment challenging.

Frame alignment in parallel typesetting is particularly tricky because it involves multiple interdependent variables and processes that must be carefully synchronized to produce visually cohesive results. Each frame may contain varying amounts of content, leading to differences in height between frames. The height of each frame depends on its content, including typeset text, insertions (e.g., footnotes), and vertical glue. Manual adjustments (e.g., custom \code{baselineSkip}, \code{parSkip}, or font sizes) are often required, further complicating alignment.

SILE’s default page builder operates on a single vertical stream, while parallel typesetting demands handling multiple streams (frames) independently while maintaining their horizontal alignment. This requires custom page-breaking and alignment logic to synchronize the streams. Manually tracking and adjusting frame heights by applying stretchy glue is essential for achieving proper alignment.

Insertions like footnotes add further complexity, as they occupy independent frames and their content flows dynamically. Ensuring these dynamic insertions do not disrupt frame alignment is challenging. When footnotes overflow, splitting them across pages can result in misalignment or compressed content if not carefully managed.

Using different font sizes or baselines for frames (e.g., for bilingual text) requires fine-tuning \code{baselineSkip}, \code{lineSkip}, or \code{parskip} settings to maintain alignment. Frames may also have varying widths or layout constraints, making it difficult to directly compare their heights.

Dynamic content, such as varying paragraph lengths, images, or tables, can lead to unpredictable behavior in each frame. Frequent recalibration is necessary to address these issues. Managing overflow content for the main frames and their footnote counterparts without disrupting alignment adds yet another layer of complexity.
To align frames reasonably, dummy content or vertical glue is often added to the shorter frame. However, such calculations must be precise to avoid visual artifacts caused by estimation errors. Even minor inaccuracies in frame height or glue calculations can result in misalignment.

SILE is primarily designed for single-frame typesetting, with limited native support for parallel or multi-frame layouts. Consequently, most parallel typesetting functionality must be implemented manually, requiring a deep understanding of SILE’s internals. Achieving proper frame alignment often involves trial and error, such as adding dummy text or phantom boxes to fine-tune the layout.

Synchronizing frames across pages involves recalculating frame heights when a new page is entered, managing footnotes, and ensuring consistent alignment. Frequent synchronization can be computationally expensive, particularly for complex or lengthy documents.

Parallel typesetting demands pixel-perfect precision to avoid noticeable misalignment. Achieving such precision often sacrifices flexibility when handling variable content. Users may need to create separate document classes tailored to specific documents.

For examples and further details, see \url{https://sile-typesetter.org/examples/parallel.sil} and the source code of \code{classes/diglot.lua}.
\end{document}
]]

return package
