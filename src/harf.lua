local module = {
  name        = "harf",
  description = "Harf",
  version     = "0.4.2",
  date        = "2019-09-07",
  license     = "GPL v2.0"
}
luatexbase.provides_module(module)

local harf = require("harf-base")

local define_font = require("harf-load")
local harf_node   = require("harf-node")

harf.callbacks = {
  define_font = define_font,
  pre_linebreak_filter = harf_node.process,
  hpack_filter = harf_node.process,
  pre_output_filter = harf_node.post_process,
  wrapup_run = harf_node.cleanup,
  finish_pdffile = harf_node.set_tounicode,
  get_glyph_string = harf_node.get_glyph_string,
}

return harf
