--- SILE inputter class.
-- @interfaces inputters

local module = require("types.module")
local inputter = pl.class(module)
inputter.type = "inputter"

function inputter:_init (options)
   self.options = options or {}
   module._init(self)
end

function inputter:classInit (options)
   options = pl.tablex.merge(options, SILE.input.options, true)
   local constructor, class
   if SILE.scratch.class_from_uses then
      constructor = SILE.scratch.class_from_uses
      class = constructor._name
   end
   class = SILE.input.class or class or options.class or "plain"
   options.class = nil -- don't pass already consumed class option to constructor
   constructor = self._docclass or constructor or SILE.require(class, "classes", true)
   -- Note SILE.documentState.documentClass is set by the instance's own :_post_init()
   constructor(options)
end

function inputter:requireClass (tree)
   local root = SILE.documentState.documentClass == nil
   if root then
      if tree.command ~= "sile" and tree.command ~= "document" then
         SU.error("This isn't a SILE document!")
      end
      self:classInit(tree.options or {})
      self:preamble()
   end
end

function inputter:process (doc)
   -- Input parsers can already return multiple ASTs, but so far we only process one
   local tree = self:parse(doc)[1]
   if SU.debugging("inputter") and SU.debugging("ast") then
      SU.debug("inputter", "Dumping AST tree before processing...\n")
      SU.dump(tree)
   end
   self:requireClass(tree)
   return SILE.process(tree)
end

function inputter:findInTree (tree, command)
   SU.deprecated("SILE.inputter:findInTree", "SU.ast.findInTree", "0.15.0", "0.17.0")
   return SU.ast.findInTree(tree, command)
end

local function process_ambles (ambles)
   for _, amble in ipairs(ambles) do
      if type(amble) == "string" then
         SILE.processFile(amble)
      elseif type(amble) == "function" then
         SU.warn(
            "Passing functions as pre/postambles is not officially sactioned and may go away without being marked as a breaking change"
         )
         amble()
      elseif type(amble) == "table" then
         local options = {}
         if amble.pack then
            amble, options = amble.pack, amble.options
         end
         if amble.type == "package" then
            local class = SILE.documentState.documentClass
            class:loadPackage(amble, options)
         else
            SILE.documentState.documentClass:initPackage(amble, options)
         end
      end
   end
end

function inputter:preamble ()
   process_ambles(SILE.input.preambles)
end

function inputter:postamble ()
   process_ambles(SILE.input.postambles)
end

return inputter
