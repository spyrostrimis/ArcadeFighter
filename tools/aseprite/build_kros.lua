-- Builds a KROS .aseprite file from the cut-out key poses (tools/aseprite/cutout_keys.py).
-- One file per costume: <prefix>_1 stance, _2 knee chamber, _3 high kick, _4 mid kick
-- (_4 made by tools/aseprite/rotate_limb.py).
-- Run: Aseprite.exe -b --script-param dir=art/kros/keys --script-param prefix=cape
--        --script-param out=art/kros/kros.aseprite --script tools/aseprite/build_kros.lua
-- Feet anchor: between the feet in the stance, the standing foot in the kicks, so the
-- body stays over the same spot.
local dir = app.params["dir"]
local prefix = app.params["prefix"]
local out = app.params["out"]
local W, H = 172, 116
local AX, AY = 74, 112    -- feet anchor on the canvas (soles land on AY)
-- measured on the 110 px stance, scaled to the poses' height (cutout_keys.py target)
local POSE_H = Image{ fromFile = dir .. "/" .. prefix .. "_1.png" }.height
local SOLE_ROW = POSE_H - 3                              -- row used to find the feet
local WAIST = math.floor(55 * POSE_H / 110 + 0.5)        -- stance rows from here down = legs layer

local function load(n)
  local img = Image{ fromFile = dir .. "/" .. prefix .. "_" .. n .. ".png" }
  local x0, x1 = nil, 0
  for x = 0, img.width - 1 do
    if app.pixelColor.rgbaA(img:getPixel(x, SOLE_ROW)) > 0 then
      x0 = x0 or x
      x1 = x
    end
  end
  local anchor = (x0 + x1) // 2   -- stance: midway between the feet; kicks: the standing boot
  return { img = img, pos = Point(AX - anchor, AY - img.height + 1) }
end

local function part(img, y0, y1)
  local p = Image(img.width, img.height, ColorMode.RGB)
  for y = y0, y1 - 1 do
    for x = 0, img.width - 1 do p:drawPixel(x, y, img:getPixel(x, y)) end
  end
  return p
end

local spr = Sprite(W, H, ColorMode.RGB)
spr.filename = out
local legs = spr.layers[1]
legs.name = "legs"
local upper = spr:newLayer()
upper.name = "upper body"

local stance, chamber, high, mid = load(1), load(2), load(3), load(4)

local n = 0
local function frame(dur)
  n = n + 1
  if n > 1 then spr:newEmptyFrame() end
  local f = spr.frames[n]
  f.duration = dur
  return f
end

-- idle: breathing, upper body sinks and rises over planted legs
local legsImg, upperImg = part(stance.img, WAIST, stance.img.height), part(stance.img, 0, WAIST)
for _, dy in ipairs({ 0, 0, 1, 1, 2, 2, 1, 1 }) do
  local f = frame(1 / 15)
  spr:newCel(legs, f, legsImg, stance.pos)
  spr:newCel(upper, f, upperImg, Point(stance.pos.x, stance.pos.y + dy))
end
local idleEnd = n

-- whole-body frames go on the upper layer; {pose, steps of 1/15 s}
local function move(seq)
  local first = n + 1
  for _, s in ipairs(seq) do
    local f = frame(s[2] / 15)
    spr:newCel(upper, f, s[1].img, s[1].pos)
  end
  return first, n
end
-- st_mk (8 startup, 4 active, 15 recovery = 27 game frames ~ 7 steps)
local mkA, mkB = move({ { chamber, 2 }, { mid, 2 }, { chamber, 2 }, { stance, 1 } })
-- st_hk (11 startup, 5 active, 23 recovery = 39 game frames ~ 10 steps)
local hkA, hkB = move({ { chamber, 3 }, { high, 3 }, { chamber, 2 }, { stance, 2 } })

-- cape on its own (tools/aseprite/cape_cutout.py): blinks and fades away at round start
local capeFrame = nil
if app.fs.isFile(dir .. "/" .. prefix .. "_only.png") then
  local capeLayer = spr:newLayer()
  capeLayer.name = "cape"
  capeFrame = frame(1 / 15)
  spr:newCel(capeLayer, capeFrame, Image{ fromFile = dir .. "/" .. prefix .. "_only.png" }, stance.pos)
end

-- tags last: frames added after a tag would stretch it
spr:newTag(1, idleEnd).name = "idle"
spr:newTag(mkA, mkB).name = "st_mk"
spr:newTag(hkA, hkB).name = "st_hk"
if capeFrame then spr:newTag(n, n).name = "cape" end

-- shared palette, indexed like a real 16-bit sprite
app.command.ColorQuantization{ ui = false, withAlpha = false, maxColors = 48, useRange = false }
app.command.ChangePixelFormat{ format = "indexed", dithering = "none" }

local s = spr:newSlice(Rectangle(AX, AY, 1, 1))
s.name = "feet"

spr:saveAs(out)
