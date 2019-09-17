Harf
====

A [HarfBuzz][harfbuzz]-based font loader and shaper for LuaTeX. It requires the
experimental `luahbtex` engine, or installing [luaharfbuzz] module for the
regular `luatex` engine.

History
-------

The initial version of the shaping code was inspired by [luatex-harfbuzz] but
was completely rewritten to use new HarfBuzz APIs and features.

There are few other projects for using HarfBuzz with LuaTeX:
* [luatex-harfbuzz]: Can access HarfBuzz through FFI, SWIG or use the
  [luaharfbuzz] module.
* [luatex-harfbuzz-shaper]: Uses [luaharfbuzz] module
* [ufylayout]: A Lua module that uses [luaharfbuzz] and provides BiDi support
  as well.

[harfbuzz]: https://github.com/harfbuzz/harfbuzz
[luaharfbuzz]: https://github.com/ufyTeX/luaharfbuzz/
[luatex-harfbuzz]: https://github.com/tatzetwerk/luatex-harfbuzz
[luatex-harfbuzz-shaper]: https://github.com/michal-h21/luatex-harfbuzz-shaper
[ufylayout]: https://github.com/ufyTeX/ufylayout
