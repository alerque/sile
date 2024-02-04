--- SILE typesetter (default/base) class.
--
-- @copyright License: MIT
-- @module typesetters.base
--

-- Typesetter base class

local typesetter = pl.class()
typesetter.type = "typesetter"
typesetter._name = "base"

-- This is the default typesetter. You are, of course, welcome to create your own.
local awful_bad = 1073741823
local inf_bad = 10000
-- local eject_penalty = -inf_bad
local supereject_penalty = 2 * -inf_bad
-- local deplorable = 100000

-- Cached typesetter related setting values that get update with a hook for fast :get()s
local _widowpenalty = 3000
local _orphanpenalty = 3000
local _parseppattern = "\r?\n[\r\n]+"
local _lskip, _rskip

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
  self:declareSettings()
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

function typesetter.declareSettings(_)

  -- Settings common to any typesetter instance.
  -- These shouldn't be re-declared and overwritten/reset in the typesetter
  -- constructor (see issue https://github.com/sile-typesetter/sile/issues/1708).
  -- On the other hand, it's fairly acceptable to have them made global:
  -- Any derived typesetter, whatever its implementation, should likely provide
  -- some logic for them (= widows, orphans, spacing, etc.)

  SILE.settings:declare({
    parameter = "typesetter.widowpenalty",
    type = "integer",
    hook = function (value) _widowpenalty = value end,
    default = _widowpenalty,
    help = "Penalty to be applied to widow lines (at the start of a paragraph)"
  })

  SILE.settings:declare({
    parameter = "typesetter.parseppattern",
    type = "string or integer",
    hook = function (value) _parseppattern = value end,
    default = _parseppattern,
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
    hook = function (value) _orphanpenalty = value end,
    default = _orphanpenalty,
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

  SILE.settings:declare({
    parameter = "typesetter.italicCorrection",
    type = "boolean",
    default = false,
    help = "Whether italic correction is activated or not"
  })

  SILE.settings:declare({
    parameter = "typesetter.softHyphen",
    type = "boolean",
    default = true,
    help = "When true, soft hyphens are rendered as discretionary breaks, otherwise they are ignored"
  })

  SILE.settings:declare({
    parameter = "typesetter.softHyphenWarning",
    type = "boolean",
    default = false,
    help = "When true, a warning is issued when a soft hyphen is encountered"
  })

  SILE.settings:declare({
    parameter = "typesetter.fixedSpacingAfterInitialEmdash",
    type = "boolean",
    default = true,
    help = "When true, em-dash starting a paragraph is considered as a speaker change in a dialogue"
  })

  -- Setup hooks so we can cache values we access a lot
  SILE.settings:registerHook("document.lskip", function (value) _lskip = value end)
  SILE.settings:registerHook("document.rskip", function (value) _rskip = value end)

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
  return _margins(_lskip, _rskip)
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
  for token in SU.gtoke(text, _parseppattern) do
    if token.separator then
      self:endline()
    else
      if SILE.settings:get("typesetter.softHyphen") then
        local warnedshy = false
        for token2 in SU.gtoke(token.string, luautf8.char(0x00AD)) do
          if token2.separator then -- soft hyphen support
            local discretionary = SILE.nodefactory.discretionary({})
            local hbox = SILE.typesetter:makeHbox({ SILE.settings:get("font.hyphenchar") })
            discretionary.prebreak = { hbox }
            table.insert(SILE.typesetter.state.nodes, discretionary)
            if not warnedshy and SILE.settings:get("typesetter.softHyphenWarning") then
              SU.warn("Soft hyphen encountered and replaced with discretionary")
            end
            warnedshy = true
          else
            self:setpar(token2.string)
          end
        end
      else
        if SILE.settings:get("typesetter.softHyphenWarning") and luautf8.match(token.string, luautf8.char(0x00AD)) then
          SU.warn("Soft hyphen encountered and ignored")
        end
        text = luautf8.gsub(token.string, luautf8.char(0x00AD), "")
        self:setpar(text)
      end
    end
  end
  SILE.traceStack:pop(pId)
end

function typesetter:initline ()
  if self.state.hmodeOnly then return end -- https://github.com/sile-typesetter/sile/issues/1718
  if (#self.state.nodes == 0) then
    self.state.nodes[#self.state.nodes+1] = SILE.nodefactory.zerohbox()
    SILE.documentState.documentClass.newPar(self)
  end
end

function typesetter:endline ()
  self:leaveHmode()
  SILE.documentState.documentClass.endPar(self)
end

-- Just compute once, to avoid unicode characters in source code.
local speakerChangePattern = "^"
   .. luautf8.char(0x2014) -- emdash
   .. "[ " .. luautf8.char(0x00A0) .. luautf8.char(0x202F) -- regular space or NBSP or NNBSP
   .. "]+"
local speakerChangeReplacement = luautf8.char(0x2014) .. " "

-- Special unshaped node subclass to handle space after a speaker change in dialogues
-- introduced by an em-dash.
local speakerChangeNode = pl.class(SILE.nodefactory.unshaped)
function speakerChangeNode:shape()
  local node = self._base.shape(self)
  local spc = node[2]
  if spc and spc.is_glue then
    -- Switch the variable space glue to a fixed kern
    node[2] = SILE.nodefactory.kern({ width = spc.width.length })
    node[2].parent = self.parent
  else
    -- Should not occur:
    -- How could it possibly be shaped differently?
    SU.warn("Speaker change logic met an unexpected case, this might be a bug.")
  end
  return node
end

-- Takes string, writes onto self.state.nodes
function typesetter:setpar (text)
  text = text:gsub("\r?\n", " "):gsub("\t", " ")
  if (#self.state.nodes == 0) then
    if not SILE.settings:get("typesetter.obeyspaces") then
      text = text:gsub("^%s+", "")
    end
    self:initline()

    if SILE.settings:get("typesetter.fixedSpacingAfterInitialEmdash") and not SILE.settings:get("typesetter.obeyspaces") then
      local speakerChange = false
      local dialogue = luautf8.gsub(text, speakerChangePattern, function ()
        speakerChange = true
        return speakerChangeReplacement
      end)
      if speakerChange then
        local node = speakerChangeNode({ text = dialogue, options = SILE.font.loadDefaults({})})
        self:pushHorizontal(node)
        return -- done here: speaker change space handling is done after nnode shaping
      end
    end
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

local function getLastShape(nodelist)
  local hasGlue
  local last
  if nodelist then
    -- The node list may contain nnodes, penalties, kern and glue
    -- We skip the latter, and retrieve the last shaped item.
    for i = #nodelist, 1, -1 do
      local n = nodelist[i]
      if n.is_nnode then
        local items = n.nodes[#n.nodes].value.items
        last = items[#items]
        break
      end
      if n.is_kern and n.subtype == "punctspace" then
        -- Some languages such as French insert a special space around
        -- punctuations. In those case, we should not need italic correction.
        break
      end
      if n.is_glue then hasGlue = true end
    end
  end
  return last, hasGlue
end
local function getFirstShape(nodelist)
  local first
  local hasGlue
  if nodelist then
    -- The node list may contain nnodes, penalties, kern and glue
    -- We skip the latter, and retrieve the first shaped item.
    for i = 1, #nodelist do
      local n = nodelist[i]
      if n.is_nnode then
        local items = n.nodes[1].value.items
        first = items[1]
        break
      end
      if n.is_kern and n.subtype == "punctspace" then
        -- Some languages such as French insert a special space around
        -- punctuations. In those case, we should not need italic correction.
        break
      end
      if n.is_glue then hasGlue = true end
    end
  end
  return first, hasGlue
end

local function fromItalicCorrection (precShape, curShape)
  local xOffset
  if not curShape or not precShape then
    xOffset = 0
  else
    -- Computing italic correction is at best heuristics.
    -- The strong assumption is that italic is slanted to the right.
    -- Thus, the part of the character that goes beyond its width is usually
    -- maximal at the top of the glyph.
    -- E.g. consider a "f", that would be the top hook extent.
    -- Pathological cases exist, such as fonts with a Q with a long tail,
    -- but these will rarely occur in usual languages. For instance, Klingon's
    -- "QaQ" might be an issue, but there's not much we can do...
    -- Another assumption is that we can distribute that extent in proportion
    -- with the next character's height.
    -- This might not work that well with non-Latin scripts.
    local d = precShape.glyphWidth + precShape.x_bearing
    local delta = d > precShape.width and d - precShape.width or 0
    xOffset = precShape.height <= curShape.height
      and delta
      or delta * curShape.height / precShape.height
  end
  return xOffset
end

local function toItalicCorrection (precShape, curShape)
  if not SILE.settings:get("typesetter.italicCorrection") then return end
  local xOffset
  if not curShape or not precShape then
    xOffset = 0
  else
    -- Same assumptions as fromItalicCorrection(), but on the starting side of
    -- the glyph.
    local d = curShape.x_bearing
    local delta = d < 0 and -d or 0
    xOffset = precShape.depth >= curShape.depth
      and delta
      or delta * precShape.depth / curShape.depth
  end
  return xOffset
end

local function isItalicLike(nnode)
  -- We could do...
  --  return nnode and string.lower(nnode.options.style) == "italic"
  -- But it's probably more robust to use the italic angle, so that
  -- thin italic, oblique or slanted fonts etc. may work too.
  local ot = require("core.opentype-parser")
  local face = SILE.font.cache(nnode.options, SILE.shaper.getFace)
  local font = ot.parseFont(face)
  return font.post.italicAngle ~= 0
end

function typesetter.shapeAllNodes (_, nodelist, inplace)
  inplace = SU.boolean(inplace, true) -- Compatibility with earlier versions
  local newNodelist = {}
  local prec
  local precShapedNodes
  for _, current in ipairs(nodelist) do
    if current.is_unshaped then
      local shapedNodes = current:shape()

      if SILE.settings:get("typesetter.italicCorrection") and prec then
        local itCorrOffset
        local isGlue
        if isItalicLike(prec) and not isItalicLike(current) then
          local precShape, precHasGlue = getLastShape(precShapedNodes)
          local curShape, curHasGlue = getFirstShape(shapedNodes)
          isGlue = precHasGlue or curHasGlue
          itCorrOffset = fromItalicCorrection(precShape, curShape)
        elseif not isItalicLike(prec) and isItalicLike(current) then
          local precShape, precHasGlue = getLastShape(precShapedNodes)
          local curShape, curHasGlue = getFirstShape(shapedNodes)
          isGlue = precHasGlue or curHasGlue
          itCorrOffset = toItalicCorrection(precShape, curShape)
        end
        if itCorrOffset and itCorrOffset ~= 0 then
          -- If one of the node contains a glue (e.g. "a \em{proof} is..."),
          -- line breaking may occur between them, so our correction shall be
          -- a glue too.
          -- Otherwise, the font change is considered to occur at a non-breaking
          -- point (e.g. "\em{proof}!") and the correction shall be a kern.
          local makeItCorrNode = isGlue and SILE.nodefactory.glue or SILE.nodefactory.kern
          newNodelist[#newNodelist+1] = makeItCorrNode({
            width = SILE.length(itCorrOffset),
            subtype = "itcorr"
          })
        end
      end

      pl.tablex.insertvalues(newNodelist, shapedNodes)

      prec = current
      precShapedNodes = shapedNodes
    else
      prec = nil
      newNodelist[#newNodelist+1] = current
    end
  end

  if not inplace then
    return newNodelist
  end

  for i =1, #newNodelist do nodelist[i] = newNodelist[i] end
  if #nodelist > #newNodelist then
    for i= #newNodelist + 1, #nodelist do nodelist[i] = nil end
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
    return "Boxed up "..(#nodelist > 500 and (#nodelist).." nodes" or SU.ast.contentToString(nodelist))
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
      pageBreakPenalty = _widowpenalty
    elseif (#lines > 1 and index == (#lines-1)) then
      pageBreakPenalty = _orphanpenalty
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
  SU.debug("pagebuilder", "Buildding page for", self.frame.id)
  self.state.lastPenalty = res
  self.frame.state.pageRestart = nil
  pageNodeList = self:runHooks("framebreak", pageNodeList)
  self:setVerticalGlue(pageNodeList, self:getTargetLength())
  self:outputLinesToPage(pageNodeList)
  return true
end

function typesetter:setVerticalGlue (pageNodeList, target)
  local glues = {}
  local gTotal = SILE.length()
  local totalHeight = SILE.length()

  local pastTop = false
  for _, node in ipairs(pageNodeList) do
    if not pastTop and not node.discardable and not node.explicit then
      -- "Ignore discardable and explicit glues at the top of a frame."
      -- See typesetter:outputLinesToPage()
      -- Note the test here doesn't check is_vglue, so will skip other
      -- discardable nodes (e.g. penalties), but it shouldn't matter
      -- for the type of computing performed here.
      pastTop = true
    end
    if pastTop then
      if not node.is_insertion then
        totalHeight:___add(node.height)
        totalHeight:___add(node.depth)
      end
      if node.is_vglue then
        table.insert(glues, node)
        gTotal:___add(node.height)
      end
    end
  end

  if totalHeight:tonumber() == 0 then
   return SU.debug("pagebuilder", "No glue adjustment needed on empty page")
  end

  local adjustment = target - totalHeight
  if adjustment:tonumber() > 0 then
    if adjustment > gTotal.stretch then
      if (adjustment - gTotal.stretch):tonumber() > SILE.settings:get("typesetter.underfulltolerance"):tonumber() then
        SU.warn("Underfull frame " .. self.frame.id .. ": " .. adjustment .. " stretchiness required to fill but only " .. gTotal.stretch .. " available")
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
        SU.warn("Overfull frame " .. self.frame.id .. ": " .. adjustment .. " shrinkability required to fit but only " .. gTotal.shrink .. " available")
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
  -- It would have been nice to avoid storing this "pastTop" into a frame
  -- state, to keep things less entangled. There are situations, though,
  -- we will have left horizontal mode (triggering output), but will later
  -- call typesetter:chuck() do deal with any remaining content, and we need
  -- to know whether some content has been output already.
  local pastTop = self.frame.state.totals.pastTop
  for _, line in ipairs(lines) do
    -- Ignore discardable and explicit glues at the top of a frame:
    -- Annoyingly, explicit glue *should* disappear at the top of a page.
    -- if you don't want that, add an empty vbox or something.
    if not pastTop and not line.discardable and not line.explicit then
      -- Note the test here doesn't check is_vglue, so will skip other
      -- discardable nodes (e.g. penalties), but it shouldn't matter
      -- for outputting.
      pastTop = true
    end
    if pastTop then
      line:outputYourself(self, line)
    end
  end
  self.frame.state.totals.pastTop = pastTop
end

function typesetter:leaveHmode (independent)
  if self.state.hmodeOnly then
    SU.error([[Paragraphs are forbidden in restricted horizontal mode.]])
  end
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
  local linestart = 1
  local lines = {}
  local nodes = self.state.nodes

  for i = 1, #breakpoints do
    local point = breakpoints[i]
    if point.position ~= 0 then
      local slice = {}
      local seenNonDiscardable = false
      for j = linestart, point.position do
        if nodes[j].is_discretionary and nodes[j].used then
          -- This is the used (prebreak) discretionary from a previous line,
          -- repeated. Replace it with a clone, changed to a postbreak.
          nodes[j] = nodes[j]:cloneAsPostbreak()
        end
        slice[#slice+1] = nodes[j]
        if nodes[j] then
          if not nodes[j].discardable then
            seenNonDiscardable = true
          end
        end
      end
      if not seenNonDiscardable then
        -- Slip lines containing only discardable nodes (e.g. glues).
        SU.debug("typesetter", "Skipping a line containing only discardable nodes")
        linestart = point.position + 1
      else
        if slice[#slice].is_discretionary then
          -- The line ends, with a discretionary:
          -- repeat it on the next line, so as to account for a potential postbreak.
          linestart = point.position
          -- And mark it as used as prebreak for now.
          slice[#slice]:markAsPrebreak()
        else
          linestart = point.position + 1
        end

        -- Then only we can add some extra margin glue...
        local mrg = self:getMargins()
        self:addrlskip(slice, mrg, point.left, point.right)

        -- And compute the line...
        local ratio = self:computeLineRatio(point.width, slice)
        local thisLine = { ratio = ratio, nodes = slice }
        lines[#lines+1] = thisLine
      end
    end
  end
  if linestart < #nodes then
    -- Abnormal, but warn so that one has a chance to check which bits
    -- are missing at output.
    SU.warn("Internal typesetter error " .. (#nodes - linestart) .. " skipped nodes")
  end
  return lines
end

function typesetter.computeLineRatio (_, breakwidth, slice)
  local naturalTotals = SILE.length()

  -- From the line end, account for the margin but skip any trailing
  -- glues (spaces to ignore) and zero boxes until we reach actual content.
  local npos = #slice
  while npos > 1 do
    if slice[npos].is_glue or slice[npos].is_zero then
      if slice[npos].value == "margin" then
        naturalTotals:___add(slice[npos].width)
      end
    else
      break
    end
    npos = npos - 1
  end

  -- Due to discretionaries, keep track of seen parent nodes
  local seenNodes = {}
  -- CODE SMELL: Not sure which node types were supposed to be skipped
  -- at initial positions in the line!
  local skipping = true

  -- Until end of actual content
  for i = 1, npos do
    local node = slice[i]
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
      local seen = node.parent and seenNodes[node.parent]
      if not seen then
        if node.used then
          if node.is_prebreak then
            naturalTotals:___add(node:prebreakWidth())
            node.height = node:prebreakHeight()
          else
            naturalTotals:___add(node:postbreakWidth())
            node.height = node:postbreakHeight()
          end
        else
          naturalTotals:___add(node:replacementWidth():absolute())
          node.height = node:replacementHeight():absolute()
        end
      end
    elseif not skipping then
      naturalTotals:___add(node.width)
    end
  end

  local _left = breakwidth:tonumber() - naturalTotals:tonumber()
  local ratio = _left / naturalTotals[_left < 0 and "shrink" or "stretch"]:tonumber()
  ratio = math.max(ratio, -1)
  return ratio, naturalTotals
end

function typesetter:chuck () -- emergency shipout everything
  self:leaveHmode(true)
  if (#self.state.outputQueue > 0) then
    SU.debug("typesetter", "Emergency shipout", #self.state.outputQueue, "lines in frame", self.frame.id)
    self:outputLinesToPage(self.state.outputQueue)
    self.state.outputQueue = {}
  end
end

-- Logic for building an hbox from content.
-- It returns the hbox and an horizontal list of (migrating) elements
-- extracted outside of it.
-- None of these are pushed to the typesetter node queue. The caller
-- is responsible of doing it, if the hbox is built for anything
-- else than e.g. measuring it. Likewise, the call has to decide
-- what to do with the migrating content.
local _rtl_pre_post = function (box, atypesetter, line)
  local advance = function () atypesetter.frame:advanceWritingDirection(box:scaledWidth(line)) end
  if atypesetter.frame:writingDirection() == "RTL" then
    advance()
    return function () end
  else
    return advance
  end
end
function typesetter:makeHbox (content)
  local recentContribution = {}
  local migratingNodes = {}

  self:pushState()
  self.state.hmodeOnly = true
  SILE.process(content)

  -- We must do a first pass for shaping the nnodes:
  -- This is also where italic correction may occur.
  local nodes = self:shapeAllNodes(self.state.nodes, false)

  -- Then we can process and measure the nodes.
  local l = SILE.length()
  local h, d = SILE.length(), SILE.length()
  for i = 1, #nodes do
    local node = nodes[i]
    if node.is_migrating then
      migratingNodes[#migratingNodes+1] = node
    elseif node.is_discretionary then
      -- HACK https://github.com/sile-typesetter/sile/issues/583
      -- Discretionary nodes have a null line contribution...
      -- But if discretionary nodes occur inside an hbox, since the latter
      -- is not line-broken, they will never be marked as 'used' and will
      -- evaluate to the replacement content (if any)...
      recentContribution[#recentContribution+1] = node
      l = l + node:replacementWidth():absolute()
      -- The replacement content may have ascenders and descenders...
      local hdisc = node:replacementHeight():absolute()
      local ddisc = node:replacementDepth():absolute()
      h = hdisc > h and hdisc or h
      d = ddisc > d and ddisc or d
      -- By the way it's unclear how this is expected to work in TTB
      -- writing direction. For other type of nodes, the line contribution
      -- evaluates to the height rather than the width in TTB, but the
      -- whole logic might then be dubious there too...
    else
      recentContribution[#recentContribution+1] = node
      l = l + node:lineContribution():absolute()
      h = node.height > h and node.height or h
      d = node.depth > d and node.depth or d
    end
  end
  self:popState()

  local hbox = SILE.nodefactory.hbox({
      height = h,
      width = l,
      depth = d,
      value = recentContribution,
      outputYourself = function (box, atypesetter, line)
        local _post = _rtl_pre_post(box, atypesetter, line)
        local ox = atypesetter.frame.state.cursorX
        local oy = atypesetter.frame.state.cursorY
        SILE.outputter:setCursor(atypesetter.frame.state.cursorX, atypesetter.frame.state.cursorY)
        SU.debug("hboxes", function ()
          -- setCursor is also invoked by the internal (wrapped) hboxes etc.
          -- so we must show our debug box before outputting its content.
          SILE.outputter:debugHbox(box, box:scaledWidth(line))
          return "Drew debug outline around hbox"
        end)
        for _, node in ipairs(box.value) do
          node:outputYourself(atypesetter, line)
        end
        atypesetter.frame.state.cursorX = ox
        atypesetter.frame.state.cursorY = oy
        _post()
      end
    })
  return hbox, migratingNodes
end

function typesetter:pushHlist (hlist)
  for _, h in ipairs(hlist) do
    self:pushHorizontal(h)
  end
end

return typesetter
