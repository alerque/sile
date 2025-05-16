-- Buggy, relies on side effects
-- luacheck: ignore solver frame
-- See https://github.com/sile-typesetter/sile/issues/694

local cassowary = require("cassowary")
local solver = cassowary.SimplexSolver()

local frame = pl.class()
frame.type = "frame"

local solverNeedsReloading = true

local widthdims = pl.Set({ "left", "right", "width" })
local heightdims = pl.Set({ "top", "bottom", "height" })
local alldims = widthdims + heightdims

frame.direction = "LTR-TTB"

-- TODO refactor with a hook table with multiple types
frame.enterHooks = {}
frame.leaveHooks = {}

function frame:_init (spec, dummy)
   SU.required(spec, "id", "frame declaration")
   self._spec = spec
   -- Redo this to read form the typesetter status on enter, not on frame creation
   local direction = SILE.documentState.direction
   if direction then
      self.direction = direction
   end
   self.id = spec.id
   self.balanced = SU.boolean(spec.balanced, false)
   self.dummy = SU.boolean(dummy or spec.dummy, false)
   for k, v in pairs(spec) do
      if not alldims[k] then
         self[k] = v
      end
   end
end

function frame:_post_init ()
   if true then return end
   self.constraints = {}
   self.variables = {}
   if not self.dummy then
      for method in pairs(alldims) do
         self.variables[method] = cassowary.Variable({ name = self._spec.id .. "_" .. method })
         self[method] = function (instance_self)
               instance_self:solve()
               local value = instance_self.variables[method].value
               return SILE.types.measurement(value)
            end
         end
         -- Add definitions of width and height
         for method in pairs(alldims) do
            if self._spec[method] then
               self:constrain(method, self._spec[method])
            end
         end
      end
end

function frame:init (typesetter)
   SU.deprecated("frame:init", "frame:connectToTypesetter", "0.16.0", "0.17.0")
   return self:connectToTypesetter(typesetter)
end

-- This gets called by us in typesetter before we start to use the frame
function frame:connectToTypesetter (typesetter)
   -- TODO make sure is solved
   if self.typesetter then
      SU.warn("Re-using frame that has already been connected to a typesetter")
   end
   -- self.state = { totals = { height = SILE.types.measurement(0) } }
   -- self:enter(typesetter)
   -- self:resetCursor()
   -- self:newLine(typesetter)
   -- self.typesetter = typesetter
   -- return self
end

function frame:resetCursor ()
   if self:pageAdvanceDirection() == "TTB" then
      self.state.cursorY = self:top()
   elseif self:pageAdvanceDirection() == "LTR" then
      self.state.cursorX = self:left()
   elseif self:pageAdvanceDirection() == "RTL" then
      self.state.cursorX = self:right()
   elseif self:pageAdvanceDirection() == "BTT" then
      self.state.cursorY = self:bottom()
   end
end

function frame:constrain (method, dimension)
   self.constraints[method] = tostring(dimension)
   self:invalidate()
end

function frame:invalidate ()
   solverNeedsReloading = true
end

function frame:relax (method)
   self.constraints[method] = nil
end

function frame:reifyConstraint (solver, method, stay)
   local constraint = self.constraints[method]
   if not constraint then
      return
   end
   constraint = SU.type(constraint) == "measurement" and constraint:tonumber() or SILE.frameParser:match(constraint)
   SU.debug("frames", "Adding constraint", self.id, function ()
      return "(" .. method .. ") = " .. tostring(constraint)
   end)
   local eq = cassowary.Equation(self.variables[method], constraint)
   solver:addConstraint(eq)
   if stay then
      solver:addStay(eq)
   end
end

function frame:addWidthHeightDefinitions (solver)
   local vars = self.variables
   solver:addConstraint(cassowary.Equation(vars.width, cassowary.minus(vars.right, vars.left)))
   solver:addConstraint(cassowary.Equation(vars.height, cassowary.minus(vars.bottom, vars.top)))
end

-- This is hideously inefficient,
-- but it's the easiest way to allow users to reconfigure frames at runtime.
function frame:solve ()
   if not solverNeedsReloading then
      return
   end
   SU.debug("frames", "Solving...")
   solver = cassowary.SimplexSolver()
   if SILE.frames.page then
      for method, _ in pairs(SILE.frames.page.constraints) do
         SILE.frames.page:reifyConstraint(solver, method, true)
      end
      SILE.frames.page:addWidthHeightDefinitions(solver)
   end
   for id, frame in pairs(SILE.frames) do
      if id ~= "page" then
         if frame.constraints then
            for method, _ in pairs(frame.constraints) do
               frame:reifyConstraint(solver, method)
            end
            frame:addWidthHeightDefinitions(solver)
         end
      end
   end
   solver:solve()
   solverNeedsReloading = false
end

function frame:writingDirection ()
   return self.direction:match("^(%a+)") or "LTR"
end

function frame:pageAdvanceDirection ()
   return self.direction:match("-(%a+)$") or "TTB"
end

function frame:advanceWritingDirection (length)
   local amount = SU.cast("number", length)
   if amount == 0 then
      return
   end
   if self:writingDirection() == "RTL" then
      self.state.cursorX = self.state.cursorX - amount
   elseif self:writingDirection() == "LTR" then
      self.state.cursorX = self.state.cursorX + amount
   elseif self:writingDirection() == "TTB" then
      self.state.cursorY = self.state.cursorY + amount
   elseif self:writingDirection() == "BTT" then
      self.state.cursorY = self.state.cursorY - amount
   end
end

function frame:advancePageDirection (length)
   local amount = SU.cast("number", length)
   if amount == 0 then
      return
   end
   if self:pageAdvanceDirection() == "TTB" then
      self.state.cursorY = self.state.cursorY + amount
   elseif self:pageAdvanceDirection() == "RTL" then
      self.state.cursorX = self.state.cursorX - amount
   elseif self:pageAdvanceDirection() == "LTR" then
      self.state.cursorX = self.state.cursorX + amount
   elseif self:pageAdvanceDirection() == "BTT" then
      self.state.cursorY = self.state.cursorY - amount
   end
end

function frame:newLine ()
   if self:writingDirection() == "LTR" then
      self.state.cursorX = self:left()
   elseif self:writingDirection() == "RTL" then
      self.state.cursorX = self:right()
   elseif self:writingDirection() == "TTB" then
      self.state.cursorY = self:top()
   elseif self:writingDirection() == "BTT" then
      self.state.cursorY = self:bottom()
   end
end

function frame:lineWidth ()
   SU.deprecated("frame:lineWidth()", "frame:getLineWidth()", "0.10.0", "0.16.0")
end

function frame:getLineWidth ()
   if self:writingDirection() == "LTR" or self:writingDirection() == "RTL" then
      return self:width()
   else
      return self:height()
   end
end

function frame:pageTarget ()
   SU.warn("Method :pageTarget() is deprecated, please use :getTargetLength()")
   return self:getTargetLength()
end

function frame:getTargetLength ()
   local direction = self:pageAdvanceDirection()
   if direction == "TTB" or direction == "BTT" then
      return self:height()
   else
      return self:width()
   end
end

function frame:enter (typesetter)
   -- TODO make sure is solved
   for i = 1, #self.enterHooks do
      self.enterHooks[i](self, typesetter)
   end
end

function frame:leave (typesetter)
   for i = 1, #self.leaveHooks do
      self.leaveHooks[i](self, typesetter)
   end
end

function frame:isAbsoluteConstraint (method)
   if not self.constraints[method] then
      return false
   end
   local constraint = SILE.frameParser:match(self.constraints[method])
   if type(constraint) ~= "table" then
      return true
   end
   if not constraint.terms then
      return false
   end
   for clv, _ in pairs(constraint.terms) do
      if clv.name and not clv.name:match("^page_") then
         return false
      end
   end
   return true
end

function frame:isMainContentFrame ()
   SU.error("Rewire isMain with registry iteration")
   if true then return true end
   local tpt = SILE.documentState.thisPageTemplate
   local frame = tpt.firstContentFrame
   while frame do
      if frame == self then
         return true
      end
      if frame.next then
         frame = SILE.getFrame(frame.next)
      else
         return false
      end
   end
   return false
end

-- Return a fresh copy of the frame based on the original specs without being "in use" by a typesetter or having any of
-- the constraints solved.
function frame:clone ()
   local spec = pl.tablex.copy(self._spec)
   local frame = self._base(spec)
   for _, k in ipairs({ "balanced", "dummy", "direction", "enterHooks", "leaveHooks" }) do
      frame[k] = self[k]
   end
   return frame
end

function frame:__tostring ()
   return self.id
end

function frame:__debug ()
   local str = "<Frame: " .. self.id .. ": "
   str = str .. " next=" .. (self.next or "nil") .. " "
   for method, dimension in pairs(self.constraints) do
      str = str .. method .. "=" .. dimension .. "; "
   end
   if self.hanmen then
      str = str .. "tate=" .. (self.tate and "true" or "false") .. "; "
      str = str .. "gridsize=" .. self.gridsize .. "; "
      str = str .. "linegap=" .. self.linegap .. "; "
      str = str .. "linelength=" .. self.linelength .. "; "
      str = str .. "linecount=" .. self.linecount .. "; "
   end
   str = str .. ">"
   return str
end

-- Work around _post_init() only getting called from base classes
local _frame = pl.class(frame)
return _frame
