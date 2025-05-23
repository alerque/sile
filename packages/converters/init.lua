local base = require("packages.base")

local package = pl.class(base)
package._name = "converters"

local lfs = require("lfs")

local applyConverter = function (source, converter)
   local extLen = string.len(converter.sourceExt)
   local targetFile = string.sub(source, 1, -extLen - 1) .. converter.targetExt

   local sourceTime = lfs.attributes(source, "modification")

   if sourceTime == nil then
      SU.debug("converters", "Source file not found", source)
      return nil -- source not found
   end

   local targetTime = lfs.attributes(targetFile, "modification")
   if (targetTime ~= nil) and (targetTime > sourceTime) then
      SU.debug("converters", "Source file already converted", source)
      return targetFile -- already converted
   end

   local command = string.gsub(converter.command, "%$(%w+)", {
      SOURCE = source,
      TARGET = targetFile,
   })

   local result = os.execute(command)
   if type(result) ~= "boolean" then
      result = (result == 0)
   end
   if result then
      SU.debug("converters", "Converted", source, "to", targetFile)
      return targetFile
   else
      return nil
   end
end

package._converters = {}

function package:register (sourceExt, targetExt, command)
   table.insert(self._converters, {
      sourceExt = sourceExt,
      targetExt = targetExt,
      command = command,
   })
end

function package:checkConverters (source)
   local resolvedSrc = SILE.resolveFile(source) or SU.error("Couldn't find file " .. source)
   for _, converter in ipairs(self._converters) do
      local extLen = string.len(converter.sourceExt)
      if (string.len(resolvedSrc) > extLen) and (string.sub(resolvedSrc, -extLen) == converter.sourceExt) then
         return applyConverter(resolvedSrc, converter)
      end
   end
   return source -- No conversion needed.
end

function package:_init ()
   base._init(self)
end

function package:registerCommands ()
   self.commands:pushWrapper("include", function (options, content, original)
      local source = SU.required(options, "src", "include (converters)")
      local result = self:checkConverters(source)
      if result then
         options["src"] = result
         original(options, content)
      else
         SU.error("Conversion failure for include '" .. source .. '"')
      end
   end)
   self.commands:pushWrapper("img", function (options, content, original)
      local source = SU.required(options, "src", "img (converters)")
      local result = self:checkConverters(source)
      if result then
         options["src"] = result
         original(options, content)
      else
         SU.error("Conversion failure for image '" .. source .. '"')
      end
   end)

   self.commands:register("converters:register", function (options, _)
      self:register(options.from, options.to, options.command)
   end)

   self.commands:register("converters:check", function (_, _)
      SU.deprecated("\\converters:check", nil, "0.14.10", "0.16.0")
   end)
end

package.documentation = [[
\begin{document}
The \autodoc:package{converters} package allows you to register additional handlers to process included files and images.
That sounds a bit abstract, so it’s best explained by example.
Suppose you have a GIF image that you would like to include in your document.
You read the documentation for the \autodoc:package{image} package and you discover that sadly GIF images are not supported.
The \autodoc:package{converters} package allows you to teach SILE how to get the GIF format into something that \em{is} supported.
We can use the ImageMagick toolkit to turn a GIF into a JPEG, and JPEGs are supported directly by SILE.

We do this by registering a converter with the \autodoc:command{\converters:register} command:

\begin[type=autodoc:codeblock]{raw}
\use[module=packages.converters]
\converters:register[from=.gif,to=.jpg,command=convert $SOURCE $TARGET]
\end{raw}

And now it just magically works:

\begin[type=autodoc:codeblock]{raw}
\img[src=hello.gif, width=50pt]
\end{raw}

This will execute the command \code{convert hello.gif hello.jpg} and include the converted \code{hello.jpg} file.

This trick also works for text files:

\begin[type=autodoc:codeblock]{raw}
\converters:register[from=.md, to=.sil, command=pandoc -o $TARGET $SOURCE]
\include[src=document.md]
\end{raw}
\end{document}
]]

return package
