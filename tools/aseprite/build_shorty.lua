-- Builds art/shorty/shorty.aseprite from the cut-out key poses (tools/aseprite/cutout_keys.py, 50 px).
-- Run: Aseprite.exe -b --script-param dir=art/shorty/keys --script-param out=art/shorty/shorty.aseprite --script tools/aseprite/build_shorty.lua
-- SHORTY is half the others' size. So far only his intro pose (hands in pockets, shown while
-- the two ladies stand by him before round 1); his fighting moves use the placeholder puppet.
-- Poses stand on the anchor by the middle of their feet.
local dir = app.params["dir"]
local out = app.params["out"]
local W, H = 72, 64
local AX, AY = 36, 60     -- feet anchor on the canvas (soles land on AY)

-- top-left position that centres the pose's feet (its bottom rows) on the anchor
local function load(name)
  local img = Image{ fromFile = dir .. "/" .. name }
  local lo, hi = img.width, -1
  for y = img.height - 3, img.height - 1 do
    for x = 0, img.width - 1 do
      if app.pixelColor.rgbaA(img:getPixel(x, y)) > 0 then
        if x < lo then lo = x end
        if x > hi then hi = x end
      end
    end
  end
  return img, Point(AX - math.floor((lo + hi) / 2), AY - img.height + 1)
end

local spr = Sprite(W, H, ColorMode.RGB)
spr.filename = out
spr.layers[1].name = "body"

local intro, introPos = load("intro_1.png")
spr.frames[1].duration = 1 / 15
spr:newCel(spr.layers[1], spr.frames[1], intro, introPos)
spr:newTag(1, 1).name = "intro"

app.command.ColorQuantization{ ui = false, withAlpha = false, maxColors = 48, useRange = false }
app.command.ChangePixelFormat{ format = "indexed", dithering = "none" }

local s = spr:newSlice(Rectangle(AX, AY, 1, 1))
s.name = "feet"

spr:saveAs(out)
