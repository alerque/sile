--- core frame registry instance
--- @module SILE.frames

--- @type frames
local registry = require("types.registry")
local frames = pl.class(registry)
frames._name = "frames"

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
   return self:push(parent, frame)
end

function frames:get (parent, id)
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
   function mt:__newindex (_name, spec)
      SU.deprecated("SILE.frames[]", "<module>.frames:new", "0.16.0", "0.17.0")
      return self:new(spec)
   end
   function mt.__pairs (_)
      SU.error("GOT PAIRS MATE")
      return pairs(self._registry)
   end
end

return frames
