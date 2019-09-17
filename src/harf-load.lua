local module = {
  name        = "harf-load",
  description = "Harf font loading",
  version     = "0.4.2",
  date        = "2019-09-07",
  license     = "GPL v2.0"
}
luatexbase.provides_module(module)

local hb = require("harf-base")

local hbfonts = hb.fonts
local hbfonts = hbfonts or {}

local cfftag  = hb.Tag.new("CFF ")
local cff2tag = hb.Tag.new("CFF2")
local os2tag  = hb.Tag.new("OS/2")
local posttag = hb.Tag.new("post")
local glyftag = hb.Tag.new("glyf")

local function trim(str)
  return str:gsub("^%s*(.-)%s*$", "%1")
end

local function split(str, sep)
  if str then
    local result = string.explode(str, sep.."+")
    for i, s in next, result do
      result[i] = trim(result[i])
    end
    return result
  end
end

local function parse(str, size)
  local name, options = str:match("%s*(.*)%s*:%s*(.*)%s*")
  local spec = {
    specification = str,
    size = size,
    variants = {}, features = {}, options = {},
  }

  name = trim(name or str)

  local filename = name:match("%[(.*)%]")
  if filename then
    -- [file]
    -- [file:index]
    filename = string.explode(filename, ":+")
    spec.file = filename[1]
    spec.index = tonumber(filename[2]) or 0
  else
    -- name
    -- name/variants
    local fontname, variants = name:match("(.-)%s*/%s*(.*)")
    spec.name = fontname or name
    spec.variants = split(variants, "/")
  end
  if options then
    options = split(options, ";+")
    for _, opt in next, options do
      if opt:find("[+-]") == 1 then
        local feature = hb.Feature.new(opt)
        spec.features[#spec.features + 1] = feature
      elseif opt ~= "" then
        local key, val = opt:match("(.*)%s*=%s*(.*)")
        if key == "language" then val = hb.Language.new(val) end
        spec.options[key or opt] = val or true
      end
    end
  end
  return spec
end

local function loadfont(spec)
  local path, index = spec.path, spec.index
  if not path then
    return nil
  end

  local key = string.format("%s:%d", path, index)
  local data = hbfonts[key]
  if data then
    return data
  end

  local hbface = hb.Face.new(path, index)
  local tags = hbface and hbface:get_table_tags()
  -- If the face has no table tags then it isn’t a valid SFNT font that
  -- HarfBuzz can handle.
  if tags then
    local hbfont = hb.Font.new(hbface)
    local upem = hbface:get_upem()

    -- The engine seems to use the font type to tell whether there is a CFF
    -- table or not, so we check for that here.
    local fonttype = nil
    local hasos2 = false
    local haspost = false
    for i = 1, #tags do
      local tag = tags[i]
      if tag == cfftag or tag == cff2tag then
        fonttype = "opentype"
      elseif tag == glyftag then
        fonttype = "truetype"
      elseif tag == os2tag then
        hasos2 = true
      elseif tag == posttag then
        haspost = true
      end
    end

    local fontextents = hbfont:get_h_extents()
    local ascender = fontextents and fontextents.ascender or upem * .8
    local descender = fontextents and fontextents.descender or upem * .2

    local gid = hbfont:get_nominal_glyph(0x0020)
    local space = gid and hbfont:get_glyph_h_advance(gid) or upem / 2

    local slant = 0
    if haspost then
      local post = hbface:get_table(posttag)
      local length = post:get_length()
      local data = post:get_data()
      if length >= 32 and string.unpack(">i4", data) <= 0x00030000 then
        local italicangle = string.unpack(">i4", data, 5) / 2^16
        if italicangle ~= 0 then
          slant = -math.tan(italicangle * math.pi / 180) * 65536.0
        end
      end
    end

    -- Load glyph metrics for all glyphs in the font. We used to do this on
    -- demand to make loading fonts faster, but hit many limitations inside
    -- the engine (mainly with shared backend fonts, where the engine would
    -- assume all fonts it decides to share load the same set of glyphs).
    --
    -- Getting glyph advances is fast enough, but glyph extents are slower
    -- especially in CFF fonts. We might want to have an option to ignore exact
    -- glyph extents and use font ascender and descender if this proved to be
    -- too slow.
    local glyphcount = hbface:get_glyph_count()
    local glyphs = {}
    for gid = 0, glyphcount - 1 do
      local width = hbfont:get_glyph_h_advance(gid)
      local height, depth, italic = nil, nil, nil
      local extents = hbfont:get_glyph_extents(gid)
      if extents then
        height = extents.y_bearing
        depth = extents.y_bearing + extents.height
        if extents.x_bearing < 0 then
          italic = -extents.x_bearing
        end
      end
      glyphs[gid] = {
        width  = width,
        height = height or ascender,
        depth  = -(depth or descender),
        italic = italic or 0,
      }
    end

    local unicodes = hbface:collect_unicodes()
    local characters = {}
    for _, uni in next, unicodes do
      characters[uni] = hbfont:get_nominal_glyph(uni)
    end

    local xheight, capheight = 0, 0
    if hasos2 then
      local os2 = hbface:get_table(os2tag)
      local length = os2:get_length()
      local data = os2:get_data()
      if length >= 96 and string.unpack(">H", data) > 1 then
        -- We don’t need much of the table, so we read from hard-coded offsets.
        xheight = string.unpack(">H", data, 87)
        capheight = string.unpack(">H", data, 89)
      end
    end

    if xheight == 0 then
      local gid = characters[120] -- x
      if gid then
        xheight = glyphs[gid].height
      else
        xheight = ascender / 2
      end
    end

    if capheight == 0 then
      local gid = characters[88] -- X
      if gid then
        capheight = glyphs[gid].height
      else
        capheight = ascender
      end
    end

    data = {
      face = hbface,
      font = hbfont,
      upem = upem,
      fonttype = fonttype,
      space = space,
      xheight = xheight,
      capheight = capheight,
      slant = slant,
      glyphs = glyphs,
      unicodes = characters,
      psname = hbface:get_name(hb.ot.NAME_ID_POSTSCRIPT_NAME),
      fullname = hbface:get_name(hb.ot.NAME_ID_FULL_NAME),
      haspng = hbface:ot_color_has_png(),
      loaded = {}, -- Cached loaded glyph data.
    }

    hbfonts[key] = data
    return data
  end
end

-- Drop illegal characters from PS Name, per the spec
-- https://docs.microsoft.com/en-us/typography/opentype/spec/name#nid6
local function sanitize(psname)
  local new = psname:gsub(".", function(c)
    local b = c:byte()
    if (b < 33 or b > 126)
    or c == "["
    or c == "]"
    or c == "("
    or c == ")"
    or c == "{"
    or c == "}"
    or c == "<"
    or c == ">"
    or c == "/"
    or c == "%"
    then
      return "-"
    end
    return c
  end)
  return new
end

local tlig = hb.texlig

local function scalefont(data, spec)
  local size = spec.size
  local options = spec.options
  local hbface = data.face
  local hbfont = data.font
  local upem = data.upem
  local space = data.space

  if size < 0 then
    size = -655.36 * size
  end

  -- We shape in font units (at UPEM) and then scale output with the desired
  -- sfont size.
  local scale = size / upem
  hbfont:set_scale(upem, upem)

  -- Populate font’s characters table.
  local glyphs = data.glyphs
  local characters = {}
  for gid, glyph in next, glyphs do
    characters[hb.CH_GID_PREFIX + gid] = {
      index  = gid,
      width  = glyph.width  * scale,
      height = glyph.height * scale,
      depth  = glyph.depth  * scale,
      italic = glyph.italic * scale,
    }
  end

  local unicodes = data.unicodes
  for uni, gid in next, unicodes do
    characters[uni] = characters[hb.CH_GID_PREFIX + gid]
  end

  -- Select font palette, we support `palette=index` option, and load the first
  -- one otherwise.
  local paletteidx = tonumber(options.palette) or 1

  -- Load CPAL palette from the font.
  local palette = nil
  if hbface:ot_color_has_palettes() and hbface:ot_color_has_layers() then
    local count = hbface:ot_color_palette_get_count()
    if paletteidx <= count then
      palette = hbface:ot_color_palette_get_colors(paletteidx)
    end
  end

  local letterspace = 0
  if options.letterspace then
    letterspace = tonumber(options.letterspace) / 100 * upem
  elseif options.kernfactor then
    letterspace = tonumber(options.kernfactor) * upem
  end
  space = space + letterspace

  local slantfactor = nil
  if options.slant then
    slantfactor = tonumber(options.slant) * 1000
  end

  local mode = nil
  local width = nil
  if options.embolden then
    mode = 2
    -- The multiplication by 7200.0/7227 is to undo the opposite conversion
    -- the engine is doing and make the final number written in the PDF file
    -- match XeTeX’s.
    width = (size * tonumber(options.embolden) / 6553.6) * (7200.0/7227)
  end

  local hscale = upem
  local extendfactor = nil
  if options.extend then
    extendfactor = tonumber(options.extend) * 1000
    hscale = hscale * tonumber(options.extend)
  end

  local vscale = upem
  local squeezefactor = nil
  if options.squeeze then
    squeezefactor = tonumber(options.squeeze) * 1000
    vscale = vscale * tonumber(options.squeeze)
  end

  if options.texlig then
    for char in next, characters do
      local ligatures = tlig[char]
      if ligatures then
        characters[char].ligatures = ligatures
      end
    end
  end

  return {
    name = spec.specification,
    filename = spec.path,
    designsize = size,
    psname = sanitize(data.psname),
    fullname = data.fullname,
    index = spec.index,
    size = size,
    units_per_em = upem,
    type = "real",
    embedding = "subset",
    tounicode = 1,
    nomath = true,
    format = data.fonttype,
    slant = slantfactor,
    mode = mode,
    width = width,
    extend = extendfactor,
    squeeze = squeezefactor,
    characters = characters,
    parameters = {
      slant = data.slant,
      space = space * scale,
      space_stretch = space * scale / 2,
      space_shrink = space * scale / 3,
      x_height = data.xheight * scale,
      quad = size,
      extra_space = space * scale / 3,
      [8] = data.capheight * scale, -- for XeTeX compatibility.
    },
    hb = {
      scale = scale,
      spec = spec,
      palette = palette,
      shared = data,
      letterspace = letterspace,
      hscale = hscale,
      vscale = vscale,
    },
  }
end

local function define_font(name, size)
  local spec = type(name) == "string" and parse(name, size) or name
  if spec.file then
    spec.path = kpse.find_file(spec.file, "truetype fonts") or
                kpse.find_file(spec.file, "opentype fonts")
  else
    -- XXX support font names
  end

  if spec.specification == "" then return nil end

  local tfmdata = nil
  local hbdata = loadfont(spec)
  if hbdata then
    tfmdata = scalefont(hbdata, spec)
  else
    tfmdata = font.read_tfm(spec.specification, spec.size)
  end
  return tfmdata
end

return define_font
