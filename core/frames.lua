--- core frame registry instance
--- @module SILE.frames

--- @type frames
local registry = require("types.registry")
local frames = pl.class(registry)
frames._name = "frames"
frames.default = false

function frames:_init ()
   registry._init(self)
end

function frames:new (parent, spec, prototype)
   if self:exists(parent, spec.id) then
      SU.debug("frames", "WARNING: Redefining frame", spec.id)
   else
      self._registry[spec.id] = {}
   end
   prototype = prototype or SILE.types.frame
   local frame = prototype(spec)
   -- If we only have one frame, make it the default
   if not self.default or spec.default then
      self.default = frame.id
   end
   return self:push(parent, frame)
end

function frames:get (parent, id)
   id = id or self.default
   local frame, last_attempt
   while not frame do
      if self:exists(parent, id) then
         frame = self:pull(parent, id)
      else
         id = id:gsub("_$", "")
         if id == last_attempt then
            break
         end
         last_attempt = id
      end
   end
   return frame or SU.warn("Couldn't find frame ID " .. id, true)
end

function frames:setDefault (_parent, id)
   self.default = id
end

function frames:getDefault (parent)
   return self:get(parent, self.default)
end

function frames:getNext (parent)
   if parent._type ~= "typesetter" then
      -- SU.dump(parent == SILE)
      SU.warn("Implement finding current frame outside of the typesetter")
   end
   local current = parent.frame
   local next = current.next
   return next and self:get(next)
end

function frames:use (parent, id)
end

function frames:makeSet(id)
end

function frames:enterSet(id)
end

function frames:clear()
end

local cassowary = require("cassowary")
local solver = cassowary.SimplexSolver()

function frames:parseComplexFrameDimension (_parent, dimension)
   local length = SILE.frameParser:match(SU.cast("string", dimension))
   if type(length) == "table" then
      local g = cassowary.Variable({ name = "t" })
      local eq = cassowary.Equation(g, length)
      SILE.frames.page:invalidate()
      solver:addConstraint(eq)
      SILE.frames.page:solve()
      SILE.frames.page:invalidate()
      return g.value
   end
   return length
end

function frames:_post_init ()
   local mt = getmetatable(self)
   function mt.__index (_, id)
      SU.deprecated("SILE.frames[]", "<module>.frames:get", "0.16.0", "0.17.0")
      return self:get(id)
   end
   function mt.__newindex (_name, spec)
      SU.deprecated("SILE.frames[]", "<module>.frames:new", "0.16.0", "0.17.0")
      return self:new(spec)
   end
end

function frames:dump ()
   for _, stack in pairs(self._registry) do
      SU.debug("frames", stack[1]:__debug())
   end
end

return frames
