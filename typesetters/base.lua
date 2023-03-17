local typesetter = pl.class()
typesetter.type = "typesetter"
typesetter._name = "base"

-- This is the default typesetter. You are, of course, welcome to create your own.
local awful_bad = 1073741823
local inf_bad = 10000
-- local eject_penalty = -inf_bad
local supereject_penalty = 2 * -inf_bad
-- local deplorable = 100000

-- Local helper class to compare pairs of margins
local _margins = pl.class({
    lskip = SILE.nodefactory.glue(),
    rskip = SILE.nodefactory.glue(),

    _init = function (self, lskip, rskip)
      self.lskip, self.rskip = lskip, rskip
    end,

    __eq = function (self, other)
      return self.lskip.width == other.lskip.width and self.rskip.width == other.rskip.width
    end

  })

local warned = false

function typesetter:init (frame)
  SU.deprecated("std.object", "pl.class", "0.13.0", "0.14.0", warned and "" or [[
  The typesetter instance inheritance system for instances has been
  refactored using a different object model. Your instance was created
  and initialized using the object copy syntax from the stdlib model.
  It has been shimmed for you using the new Penlight model, but this may
  lead to unexpected behaviour. Please update your code to use the new
  Penlight based inheritance model.]])
  warned = true
  self:_init(frame)
end

function typesetter:_init (frame)

  SILE.settings:declare({
    parameter = "typesetter.widowpenalty",
    type = "integer",
    default = 3000,
    help = "Penalty to be applied to widow lines (at the start of a paragraph)"
  })

  SILE.settings:declare({
    parameter = "typesetter.parseppattern",
    type = "string or integer",
    default = "\r?\n[\r\n]+",
    help = "Lua pattern used to separate paragraphs"
  })

  SILE.settings:declare({
    parameter = "typesetter.obeyspaces",
    type = "boolean or nil",
    default = nil,
    help = "Whether to ignore paragraph initial spaces"
  })

  SILE.settings:declare({
    parameter = "typesetter.orphanpenalty",
    type = "integer",
    default = 3000,
    help = "Penalty to be applied to orphan lines (at the end of a paragraph)"
  })

  SILE.settings:declare({
    parameter = "typesetter.parfillskip",
    type = "glue",
    default = SILE.nodefactory.glue("0pt plus 10000pt"),
    help = "Glue added at the end of a paragraph"
  })

  SILE.settings:declare({
    parameter = "document.letterspaceglue",
    type = "glue or nil",
    default = nil,
    help = "Glue added between tokens"
  })

  SILE.settings:declare({
    parameter = "typesetter.underfulltolerance",
    type = "length or nil",
    default = SILE.length("1em"),
    help = "Amount a page can be underfull without warning"
  })

  SILE.settings:declare({
    parameter = "typesetter.overfulltolerance",
    type = "length or nil",
    default = SILE.length("5pt"),
    help = "Amount a page can be overfull without warning"
  })

  SILE.settings:declare({
    parameter = "typesetter.breakwidth",
    type = "measurement or nil",
    default = nil,
    help = "Width to break lines at"
  })

  self.hooks = {}
  self.breadcrumbs = SU.breadcrumbs()

  self.frame = nil
  self.stateQueue = {}
  self:initFrame(frame)
  self:initState()
  -- In case people use stdlib prototype syntax off of the instantiated typesetter...
  getmetatable(self).__call = self.init
  return self
end

function typesetter:initState ()
  self.state = {
    nodes = {},
    outputQueue = {},
    lastBadness = awful_bad,
  }
end

function typesetter:initFrame (frame)
  if frame then
    self.frame = frame
    self.frame:init(self)
  end
end

function typesetter.getMargins ()
  return _margins(SILE.settings:get("document.lskip"), SILE.settings:get("document.rskip"))
end

function typesetter.setMargins (_, margins)
  SILE.settings:set("document.lskip", margins.lskip)
  SILE.settings:set("document.rskip", margins.rskip)
end

function typesetter:pushState ()
  self.stateQueue[#self.stateQueue+1] = self.state
  self:initState()
end

function typesetter:popState (ncount)
  local offset = ncount and #self.stateQueue - ncount or nil
  self.state = table.remove(self.stateQueue, offset)
  if not self.state then SU.error("Typesetter state queue empty") end
end

function typesetter:isQueueEmpty ()
  if not self.state then return nil end
  return #self.state.nodes == 0 and #self.state.outputQueue == 0
end

function typesetter:vmode ()
  return #self.state.nodes == 0
end

function typesetter:debugState ()
  print("\n---\nI am in "..(self:vmode() and "vertical" or "horizontal").." mode")
  print("Writing into " .. tostring(self.frame))
  print("Recent contributions: ")
  for i = 1, #(self.state.nodes) do
    io.stderr:write(self.state.nodes[i].. " ")
  end
  print("\nVertical list: ")
  for i = 1, #(self.state.outputQueue) do
    print("  "..self.state.outputQueue[i])
  end
end

-- Boxy stuff
function typesetter:pushHorizontal (node)
  self:initline()
  self.state.nodes[#self.state.nodes+1] = node
  return node
end

function typesetter:pushVertical (vbox)
  self.state.outputQueue[#self.state.outputQueue+1] = vbox
  return vbox
end

function typesetter:pushHbox (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushHorizontal() to pass a premade node instead of a spec") end
  local ntype = SU.type(spec)
  local node = (ntype == "hbox" or ntype == "zerohbox") and spec or SILE.nodefactory.hbox(spec)
  return self:pushHorizontal(node)
end

function typesetter:pushUnshaped (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushHorizontal() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "unshaped" and spec or SILE.nodefactory.unshaped(spec)
  return self:pushHorizontal(node)
end

function typesetter:pushGlue (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushHorizontal() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "glue" and spec or SILE.nodefactory.glue(spec)
  return self:pushHorizontal(node)
end

function typesetter:pushExplicitGlue (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushHorizontal() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "glue" and spec or SILE.nodefactory.glue(spec)
  node.explicit = true
  node.discardable = false
  return self:pushHorizontal(node)
end

function typesetter:pushPenalty (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushHorizontal() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "penalty" and spec or SILE.nodefactory.penalty(spec)
  return self:pushHorizontal(node)
end

function typesetter:pushMigratingMaterial (material)
  local node = SILE.nodefactory.migrating({ material = material })
  return self:pushHorizontal(node)
end

function typesetter:pushVbox (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushVertical() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "vbox" and spec or SILE.nodefactory.vbox(spec)
  return self:pushVertical(node)
end

function typesetter:pushVglue (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushVertical() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "vglue" and spec or SILE.nodefactory.vglue(spec)
  return self:pushVertical(node)
end

function typesetter:pushExplicitVglue (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushVertical() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "vglue" and spec or SILE.nodefactory.vglue(spec)
  node.explicit = true
  node.discardable = false
  return self:pushVertical(node)
end

function typesetter:pushVpenalty (spec)
  -- if SU.type(spec) ~= "table" then SU.warn("Please use pushVertical() to pass a premade node instead of a spec") end
  local node = SU.type(spec) == "penalty" and spec or SILE.nodefactory.penalty(spec)
  return self:pushVertical(node)
end

-- Actual typesetting functions
function typesetter:typeset (text)
  text = tostring(text)
  if text:match("^%\r?\n$") then return end
  local pId = SILE.traceStack:pushText(text)
  for token in SU.gtoke(text, SILE.settings:get("typesetter.parseppattern")) do
    if token.separator then
      self:endline()
    else
      self:setpar(token.string)
    end
  end
  SILE.traceStack:pop(pId)
end

function typesetter:initline ()
  if (#self.state.nodes == 0) then
    self.state.nodes[#self.state.nodes+1] = SILE.nodefactory.zerohbox()
    SILE.documentState.documentClass.newPar(self)
  end
end

function typesetter:endline ()
  self:leaveHmode()
  SILE.documentState.documentClass.endPar(self)
end

-- Takes string, writes onto self.state.nodes
function typesetter:setpar (text)
  text = text:gsub("\r?\n", " "):gsub("\t", " ")
  if (#self.state.nodes == 0) then
    if not SILE.settings:get("typesetter.obeyspaces") then
      text = text:gsub("^%s+", "")
    end
    self:initline()
  end
  if #text >0 then
    self:pushUnshaped({ text = text, options= SILE.font.loadDefaults({})})
  end
end

function typesetter:breakIntoLines (nodelist, breakWidth)
  self:shapeAllNodes(nodelist)
  local breakpoints = SILE.linebreak:doBreak(nodelist, breakWidth)
  return self:breakpointsToLines(breakpoints)
end

function typesetter.shapeAllNodes (_, nodelist)
  local newNl = {}
  for i = 1, #nodelist do
    if nodelist[i].is_unshaped then
      pl.tablex.insertvalues(newNl, nodelist[i]:shape())
    else
      newNl[#newNl+1] = nodelist[i]
    end
  end
  for i =1, #newNl do nodelist[i]=newNl[i] end
  if #nodelist > #newNl then
    for i=#newNl+1, #nodelist do nodelist[i]=nil end
  end
end

-- Empties self.state.nodes, breaks into lines, puts lines into vbox, adds vbox to
-- Turns a node list into a list of vboxes
function typesetter:boxUpNodes ()
  local nodelist = self.state.nodes
  if #nodelist == 0 then return {} end
  for j = #nodelist, 1, -1 do
    if not nodelist[j].is_migrating then
      if nodelist[j].discardable then
        table.remove(nodelist, j)
      else
        break
      end
    end
  end
  while (#nodelist > 0 and nodelist[1].is_penalty) do table.remove(nodelist, 1) end
  if #nodelist == 0 then return {} end
  self:shapeAllNodes(nodelist)
  local parfillskip = SILE.settings:get("typesetter.parfillskip")
  parfillskip.discardable = false
  self:pushGlue(parfillskip)
  self:pushPenalty(-inf_bad)
  SU.debug("typesetter", function ()
    return "Boxed up "..(#nodelist > 500 and (#nodelist).." nodes" or SU.contentToString(nodelist))
  end)
  local breakWidth = SILE.settings:get("typesetter.breakwidth") or self.frame:getLineWidth()
  local lines = self:breakIntoLines(nodelist, breakWidth)
  local vboxes = {}
  for index=1, #lines do
    local line = lines[index]
    local migrating = {}
    -- Move any migrating material
    local nodes = {}
    for i =1, #line.nodes do
      local node = line.nodes[i]
      if node.is_migrating then
        for j=1, #node.material do migrating[#migrating+1] = node.material[j] end
      else
        nodes[#nodes+1] = node
      end
    end
    local vbox = SILE.nodefactory.vbox({ nodes = nodes, ratio = line.ratio })
    local pageBreakPenalty = 0
    if (#lines > 1 and index == 1) then
      pageBreakPenalty = SILE.settings:get("typesetter.widowpenalty")
    elseif (#lines > 1 and index == (#lines-1)) then
      pageBreakPenalty = SILE.settings:get("typesetter.orphanpenalty")
    end
    vboxes[#vboxes+1] = self:leadingFor(vbox, self.state.previousVbox)
    vboxes[#vboxes+1] = vbox
    for i=1, #migrating do vboxes[#vboxes+1] = migrating[i] end
    self.state.previousVbox = vbox
    if pageBreakPenalty > 0 then
      SU.debug("typesetter", "adding penalty of", pageBreakPenalty, "after", vbox)
      vboxes[#vboxes+1] = SILE.nodefactory.penalty(pageBreakPenalty)
    end
  end
  return vboxes
end

function typesetter.pageTarget (_)
  SU.deprecated("SILE.typesetter:pageTarget", "SILE.typesetter:getTargetLength", "0.13.0", "0.14.0")
end

function typesetter:getTargetLength ()
  return self.frame:getTargetLength()
end

function typesetter:registerHook (category, func)
  if not self.hooks[category] then self.hooks[category] = {} end
  table.insert(self.hooks[category], func)
end

function typesetter:runHooks (category, data)
  if not self.hooks[category] then return data end
  for _, func in ipairs(self.hooks[category]) do
    data = func(self, data)
  end
  return data
end

function typesetter:registerFrameBreakHook (func)
  self:registerHook("framebreak", func)
end

function typesetter:registerNewFrameHook (func)
  self:registerHook("newframe", func)
end

function typesetter:registerPageEndHook (func)
  self:registerHook("pageend", func)
end

function typesetter:buildPage ()
  local pageNodeList
  local res
  if self:isQueueEmpty() then return false end
  if SILE.scratch.insertions then SILE.scratch.insertions.thisPage = {} end
  pageNodeList, res = SILE.pagebuilder:findBestBreak({
    vboxlist = self.state.outputQueue,
    target   = self:getTargetLength(),
    restart  = self.frame.state.pageRestart
  })
  if not pageNodeList then -- No break yet
    -- self.frame.state.pageRestart = res
    self:runHooks("noframebreak")
    return false
  end
  self.state.lastPenalty = res
  self.frame.state.pageRestart = nil
  pageNodeList = self:runHooks("framebreak", pageNodeList)
  self:setVerticalGlue(pageNodeList, self:getTargetLength())
  self:outputLinesToPage(pageNodeList)
  return true
end

function typesetter.setVerticalGlue (_, pageNodeList, target)
  local glues = {}
  local gTotal = SILE.length()
  local totalHeight = SILE.length()
  for _, node in ipairs(pageNodeList) do
    if not node.is_insertion then
      totalHeight:___add(node.height)
      totalHeight:___add(node.depth)
    end
    if node.is_vglue then
      table.insert(glues, node)
      gTotal:___add(node.height)
    end
  end
  local adjustment = target - totalHeight
  if adjustment:tonumber() > 0 then
    if adjustment > gTotal.stretch then
      if (adjustment - gTotal.stretch):tonumber() > SILE.settings:get("typesetter.underfulltolerance"):tonumber() then
        SU.warn("Underfull frame: " .. adjustment .. " stretchiness required to fill but only " .. gTotal.stretch .. " available")
      end
      adjustment = gTotal.stretch
    end
    if gTotal.stretch:tonumber() > 0 then
      for i = 1, #glues do
        local g = glues[i]
        g:adjustGlue(adjustment:tonumber() * g.height.stretch:absolute() / gTotal.stretch)
      end
    end
  elseif adjustment:tonumber() < 0 then
    adjustment = 0 - adjustment
    if adjustment > gTotal.shrink then
      if (adjustment - gTotal.shrink):tonumber() > SILE.settings:get("typesetter.overfulltolerance"):tonumber() then
        SU.warn("Overfull frame: " .. adjustment .. " shrinkability required to fit but only " .. gTotal.shrink .. " available")
      end
      adjustment = gTotal.shrink
    end
    if gTotal.shrink:tonumber() > 0 then
      for i = 1, #glues do
        local g  = glues[i]
        g:adjustGlue(-adjustment:tonumber() * g.height.shrink:absolute() / gTotal.shrink)
      end
    end
  end
  SU.debug("pagebuilder", "Glues for this page adjusted by", adjustment, "drawn from", gTotal)
end

function typesetter:initNextFrame ()
  local oldframe = self.frame
  self.frame:leave(self)
  if #self.state.outputQueue == 0 then
    self.state.previousVbox = nil
  end
  if self.frame.next and self.state.lastPenalty > supereject_penalty then
    self:initFrame(SILE.getFrame(self.frame.next))
  elseif not self.frame:isMainContentFrame() then
    if #self.state.outputQueue > 0 then
      SU.warn("Overfull content for frame " .. self.frame.id)
      self:chuck()
    end
  else
    self:runHooks("pageend")
    SILE.documentState.documentClass:endPage()
    self:initFrame(SILE.documentState.documentClass:newPage())
  end

  if not SU.feq(oldframe:getLineWidth(), self.frame:getLineWidth()) then
    self:pushBack()
    -- Some what of a hack below.
    -- Before calling this method, we were in vertical mode...
    -- pushback occurred, and it seems it messes up a bit...
    -- Regardless what it does, at the end, we ought to be in vertical mode
    -- again:
    self:leaveHmode()
  else
    -- If I have some things on the vertical list already, they need
    -- proper top-of-frame leading applied.
    if #self.state.outputQueue > 0 then
      local lead = self:leadingFor(self.state.outputQueue[1], nil)
      if lead then
        table.insert(self.state.outputQueue, 1, lead)
      end
    end
  end
  self:runHooks("newframe")

end

function typesetter:pushBack ()
  SU.debug("typesetter", "Pushing back", #self.state.outputQueue, "nodes")
  local oldqueue = self.state.outputQueue
  self.state.outputQueue = {}
  self.state.previousVbox = nil
  local lastMargins = self:getMargins()
  for _, vbox in ipairs(oldqueue) do
    SU.debug("pushback", "process box", vbox)
    if vbox.margins and vbox.margins ~= lastMargins then
      SU.debug("pushback", "new margins", lastMargins, vbox.margins)
      if not self.state.grid then self:endline() end
      self:setMargins(vbox.margins)
    end
    if vbox.explicit then
      SU.debug("pushback", "explicit", vbox)
      self:endline()
      self:pushExplicitVglue(vbox)
    elseif vbox.is_insertion then
      SU.debug("pushback", "pushBack", "insertion", vbox)
      SILE.typesetter:pushMigratingMaterial({ material = { vbox } })
    elseif not vbox.is_vglue and not vbox.is_penalty then
      SU.debug("pushback", "not vglue or penalty", vbox.type)
      local discardedFistInitLine = false
      if (#self.state.nodes == 0) then
        -- Setup queue but avoid calling newPar
        self.state.nodes[#self.state.nodes+1] = SILE.nodefactory.zerohbox()
      end
      for i, node in ipairs(vbox.nodes) do
        if node.is_glue and not node.discardable then
          self:pushHorizontal(node)
        elseif node.is_glue and node.value == "margin" then
          SU.debug("pushback", "discard", node.value, node)
        elseif node.is_discretionary then
          SU.debug("pushback", "re-mark discretionary as unused", node)
          node.used = false
          if i == 1 then
            SU.debug("pushback", "keep first discretionary", node)
            self:pushHorizontal(node)
          else
            SU.debug("pushback", "discard all other discretionaries", node)
          end
        elseif node.is_zero then
          if discardedFistInitLine then self:pushHorizontal(node) end
          discardedFistInitLine = true
        elseif node.is_penalty then
          if not discardedFistInitLine then self:pushHorizontal(node) end
        else
          node.bidiDone = true
          self:pushHorizontal(node)
        end
      end
    else
      SU.debug("pushback", "discard", vbox.type)
    end
    lastMargins = vbox.margins
    -- self:debugState()
  end
  while self.state.nodes[#self.state.nodes]
  and (self.state.nodes[#self.state.nodes].is_penalty
    or self.state.nodes[#self.state.nodes].is_zero) do
    self.state.nodes[#self.state.nodes] = nil
  end
end

function typesetter:outputLinesToPage (lines)
  SU.debug("pagebuilder", "OUTPUTTING frame", self.frame.id)
  for _, line in ipairs(lines) do
    -- Annoyingly, explicit glue *should* disappear at the top of a page.
    -- if you don't want that, add an empty vbox or something.
    if not self.frame.state.totals.pastTop and not line.discardable and not line.explicit then
      self.frame.state.totals.pastTop = true
    end
    if self.frame.state.totals.pastTop then
      line:outputYourself(self, line)
    end
  end
end

function typesetter:leaveHmode (independent)
  SU.debug("typesetter", "Leaving hmode")
  local margins = self:getMargins()
  local vboxlist = self:boxUpNodes()
  self.state.nodes = {}
  -- Push output lines into boxes and ship them to the page builder
  for _, vbox in ipairs(vboxlist) do
    vbox.margins = margins
    self:pushVertical(vbox)
  end
  if independent then return end
  if self:buildPage() then
    self:initNextFrame()
  end
end

function typesetter:inhibitLeading ()
  self.state.previousVbox = nil
end

function typesetter.leadingFor (_, vbox, previous)
  -- Insert leading
  SU.debug("typesetter", "   Considering leading between two lines:")
  SU.debug("typesetter", "   1)", previous)
  SU.debug("typesetter", "   2)", vbox)
  if not previous then return SILE.nodefactory.vglue() end
  local prevDepth = previous.depth
  SU.debug("typesetter", "   Depth of previous line was", prevDepth)
  local bls = SILE.settings:get("document.baselineskip")
  local depth = bls.height:absolute() - vbox.height:absolute() - prevDepth:absolute()
  SU.debug("typesetter", "   Leading height =", bls.height, "-", vbox.height, "-", prevDepth, "=", depth)

  -- the lineskip setting is a vglue, but we need a version absolutized at this point, see #526
  local lead = SILE.settings:get("document.lineskip").height:absolute()
  if depth > lead then
    return SILE.nodefactory.vglue(SILE.length(depth.length, bls.height.stretch, bls.height.shrink))
  else
    return SILE.nodefactory.vglue(lead)
  end
end

function typesetter:addrlskip (slice, margins, hangLeft, hangRight)
  local LTR = self.frame:writingDirection() == "LTR"
  local rskip = margins[LTR and "rskip" or "lskip"]
  if not rskip then rskip = SILE.nodefactory.glue(0) end
  if hangRight and hangRight > 0 then
    rskip = SILE.nodefactory.glue({ width = rskip.width:tonumber() + hangRight })
  end
  rskip.value = "margin"
  -- while slice[#slice].discardable do table.remove(slice, #slice) end
  table.insert(slice, rskip)
  table.insert(slice, SILE.nodefactory.zerohbox())
  local lskip = margins[LTR and "lskip" or "rskip"]
  if not lskip then lskip = SILE.nodefactory.glue(0) end
  if hangLeft and hangLeft > 0 then
    lskip = SILE.nodefactory.glue({ width = lskip.width:tonumber() + hangLeft })
  end
  lskip.value = "margin"
  while slice[1].discardable do table.remove(slice, 1) end
  table.insert(slice, 1, lskip)
  table.insert(slice, 1, SILE.nodefactory.zerohbox())
end

function typesetter:breakpointsToLines (breakpoints)
  local linestart = 0
  local lines = {}
  local nodes = self.state.nodes

  for i = 1, #breakpoints do
    local point = breakpoints[i]
    if point.position ~= 0 then
      local slice = {}
      local seenHbox = 0
      -- local toss = 1
      for j = linestart, point.position do
        slice[#slice+1] = nodes[j]
        if nodes[j] then
          -- toss = 0
          if nodes[j].is_box or nodes[j].is_discretionary then seenHbox = 1 end
        end
      end
      if seenHbox == 0 then break end
      local mrg = self:getMargins()
      self:addrlskip(slice, mrg, point.left, point.right)
      local ratio = self:computeLineRatio(point.width, slice)
      -- TODO see bug 620
      -- if math.abs(ratio) > 1 then SU.warn("Using ratio larger than 1" .. ratio) end
      local thisLine = { ratio = ratio, nodes = slice }
      lines[#lines+1] = thisLine
      if slice[#slice].is_discretionary then
        linestart = point.position
      else
        linestart = point.position + 1
      end
    end
  end
  --self.state.nodes = nodes.slice(linestart+1,nodes.length)
  return lines
end

function typesetter.computeLineRatio (_, breakwidth, slice)
  -- This somewhat wrong, see #1362.
  -- This is a very partial workaround, at least made consistent with the
  -- nnode outputYourself routine expectation (which is somewhat wrong too)
  local naturalTotals = SILE.length()

  local n = #slice
  while n > 1 do
    if slice[n].is_glue or slice[n].is_zero then
      if slice[n].value ~= "margin" then
        naturalTotals:___sub(slice[n].width)
      end
    elseif slice[n].is_discretionary then
      slice[n].used = true
      if slice[n].parent then
        slice[n].parent.hyphenated = true
      end
      naturalTotals:___sub(slice[n]:replacementWidth())
      naturalTotals:___add(slice[n]:prebreakWidth())
      slice[n].height = slice[n]:prebreakHeight()
      break
    else
      break
    end
    n = n - 1
  end

  local seenNodes = {}
  local skipping = true
  for i, node in ipairs(slice) do
    if node.is_box then
      skipping = false
      if node.parent and not node.parent.hyphenated then
        if not seenNodes[node.parent] then
          naturalTotals:___add(node.parent:lineContribution())
        end
        seenNodes[node.parent] = true
      else
        naturalTotals:___add(node:lineContribution())
      end
    elseif node.is_penalty and node.penalty == -inf_bad then
      skipping = false
    elseif node.is_discretionary then
      skipping = false
      if node.used then
        naturalTotals:___add(node:replacementWidth())
        slice[i].height = slice[i]:replacementHeight():absolute()
      end
    elseif not skipping then
      naturalTotals:___add(node.width)
    end
  end

  if slice[1].is_discretionary then
    naturalTotals:___sub(slice[1]:replacementWidth())
    naturalTotals:___add(slice[1]:postbreakWidth())
    slice[1].height = slice[1]:postbreakHeight()
  end
  local _left = breakwidth:tonumber() - naturalTotals:tonumber()
  local ratio = _left / naturalTotals[_left < 0 and "shrink" or "stretch"]:tonumber()
  -- Here a previous comment said: TODO: See bug 620
  -- But the latter seems to suggest capping the ratio if greater than 1, which is wrong.
  ratio = math.max(ratio, -1)
  return ratio, naturalTotals
end

function typesetter:chuck () -- emergency shipout everything
  self:leaveHmode(true)
  self:outputLinesToPage(self.state.outputQueue)
  self.state.outputQueue = {}
end

return typesetter
