# This file contains the common helper functions that we'd like to share among
# the **Lexer**, **Rewriter**, and the **Nodes**. Merge objects, flatten
# arrays, count characters, that sort of thing.

# Peek at the beginning of a given string to see if it matches a sequence.
exports.starts = (string, literal, start) ->
  literal is string.substr start, literal.length

# Peek at the end of a given string to see if it matches a sequence.
exports.ends = (string, literal, back) ->
  len = literal.length
  literal is string.substr string.length - len - (back or 0), len

# Repeat a string `n` times.
exports.repeat = repeat = (str, n) ->
  # Use clever algorithm to have O(log(n)) string concatenation operations.
  res = ''
  while n > 0
    res += str if n & 1
    n >>>= 1
    str += str
  res

# Trim out all falsy values from an array.
exports.compact = (array) ->
  item for item in array when item

# Merge objects, returning a fresh copy with attributes from both sides.
# Used every time `Base#compile` is called, to allow properties in the
# options hash to propagate down the tree without polluting other branches.
exports.merge = (options, overrides) ->
  extend (extend {}, options), overrides

# Extend a source object with the properties of another object (shallow copy).
extend = exports.extend = (object, properties) ->
  for key, val of properties
    object[key] = val
  object

# Return a flattened version of an array.
# Handy for getting a list of `children` from the nodes.
exports.flatten = flatten = (array) ->
  flattened = []
  for element in array
    if element instanceof Array
      flattened = flattened.concat flatten element
    else
      flattened.push element
  flattened

# Delete a key from an object, returning the value. Useful when a node is
# looking for a particular method in an options hash.
exports.del = (obj, key) ->
  val =  obj[key]
  delete obj[key]
  val

# Gets the last item of an array(-like) object.
exports.last = last = (array, back) -> array[array.length - (back or 0) - 1]

# Typical Array::some
exports.some = Array::some ? (fn) ->
  return true for e in this when fn e
  false

# Simple function for inverting Literate CoffeeScript code by putting the
# documentation in comments, producing a string of CoffeeScript code that
# can be compiled "normally".
exports.invertLiterate = (code) ->
  maybe_code = true
  lines = for line in code.split('\n')
    if maybe_code and /^([ ]{4}|[ ]{0,3}\t)/.test line
      line
    else if maybe_code = /^\s*$/.test line
      line
    else
      '# ' + line
  lines.join '\n'

# Merge two jison-style location data objects together.
# If `last` is not provided, this will simply return `first`.
buildLocationData = (first, last) ->
  if not last
    first
  else
    first_line: first.first_line
    first_column: first.first_column
    last_line: last.last_line
    last_column: last.last_column
    file_num: last.file_num

# This returns a function which takes an object as a parameter, and if that
# object is an AST node, updates that object's locationData.
# The object is returned either way.
exports.addLocationDataFn = (first, last) ->
  (obj) ->
    if ((typeof obj) is 'object') and (!!obj['updateLocationDataIfMissing'])
      obj.updateLocationDataIfMissing buildLocationData(first, last)

    return obj

# Convert jison location data to a string.
# `obj` can be a token, or a locationData.
exports.locationDataToString = (ld) ->
  return '<unknown location>' if not ld
  loc = ''
  if filename = filenames[ld.file_num ? filenames.length-1]
    loc += filename+':'
  loc += (ld.first_line + 1) + ':' + (ld.first_column + 1)

# A `.coffee.md` compatible version of `basename`, that returns the file sans-extension.
exports.baseFileName = (file, stripExt = no, useWinPathSep = no) ->
  pathSep = if useWinPathSep then /\\|\// else /\//
  parts = file.split(pathSep)
  file = parts[parts.length - 1]
  return file unless stripExt and file.indexOf('.') >= 0
  parts = file.split('.')
  parts.pop()
  parts.pop() if parts[parts.length - 1] is 'coffee' and parts.length > 1
  parts.join('.')

# Determine if a filename represents a CoffeeScript file.
exports.isCoffee = (file) -> /\.((lit)?coffee|coffee\.md)$/.test file

# Determine if a filename represents a Literate CoffeeScript file.
exports.isLiterate = (file) -> /\.(litcoffee|coffee\.md)$/.test file

# Throws a SyntaxError from a given location.
# The error's `toString` will return an error message following the "standard"
# format <filename>:<line>:<col>: <message> plus the line with the error and a
# marker showing where the error is.
exports.throwSyntaxError = (message, location) ->
  err = new SyntaxError message
  err.location = location
  # Instead of showing the compiler's stacktrace, show our custom error message
  # (this is useful when the error bubbles up in Node.js applications that
  # compile CoffeeScript for example).
  err.toString = syntaxErrorToString
  err.stack = err.toString()
  throw err


# Lists of coffeescript sources and filenames, for every bit of code that is
# tokenized. It's indexed by `file_num`, which is set on each of the parser 
# nodes and is passed to the lexer.
exports.scripts = scripts = []
exports.filenames = filenames = []

exports.getFileNum = (source, filename) ->
  fileNum = scripts.length
  scripts[fileNum] = source
  filenames[fileNum] = filename
  fileNum


syntaxErrorToString = ->
  return Error::toString.call @ unless @location

  {first_line, first_column, last_line, last_column, file_num} = @location
  file_num ?= scripts.length-1 # we're parsing/lexing the most recent script
  last_line ?= first_line
  last_column ?= first_column

  filename = filenames[file_num] or '[stdin]'
  codeLine = scripts[file_num]?.split('\n')[first_line] || ''
  start    = first_column
  # Show only the first line on multi-line errors.
  end      = if first_line is last_line then last_column + 1 else codeLine.length
  marker   = codeLine.substr(0,start).replace(/[^\t]/g,' ') + (codeLine+" ").substring(start,end).replace(/[^\t]/g,'^')

  # Check to see if we're running on a color-enabled TTY.
  if process?
    colorsEnabled = process.stdout.isTTY and not process.env.NODE_DISABLE_COLORS

  if @colorful ? colorsEnabled
    colorize = (str) -> "\x1B[1;31m#{str}\x1B[0m"
    codeLine = codeLine[...start] + colorize(codeLine[start...end]) + codeLine[end..]
    marker   = colorize marker

  """
    #{filename}:#{first_line + 1}:#{first_column + 1}: error: #{@message}
    #{codeLine}
    #{marker}
  """

exports.nameWhitespaceCharacter = (string) ->
  switch string
    when ' ' then 'space'
    when '\n' then 'newline'
    when '\r' then 'carriage return'
    when '\t' then 'tab'
    else string
