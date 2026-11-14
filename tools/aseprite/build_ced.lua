-- Builds art/ced/ced.aseprite from the cut-out key poses (tools/aseprite/cutout_keys.py).
-- Run: Aseprite.exe -b --script-param dir=art/ced/keys --script-param out=art/ced/ced.aseprite --script tools/aseprite/build_ced.lua
-- Poses are lined up by the back foot, so the feet stay planted between frames.
local dir = app.params["dir"]
local out = app.params["out"]
local W, H = 128, 118
local AX, AY = 48, 114    -- feet anchor on the canvas (soles land on AY)
-- measured on the 113 px stance, scaled to the poses' height (cutout_keys.py target)
local POSE_H = Image{ fromFile = dir .. "/hp_1.png" }.height
local k = POSE_H / 113
local FOOT_ROW = POSE_H - 5                        -- row used to find the back foot's left edge
local BACK_TO_ANCHOR = math.floor(44 * k + 0.5)    -- back foot's left edge -> anchor
local WAIST = math.floor(52 * k + 0.5)             -- stance rows from here down = legs layer

local function load(name)
  local img = Image{ fromFile = dir .. "/" .. name }
  local left = 0
  for x = 0, img.width - 1 do
    if app.pixelColor.rgbaA(img:getPixel(x, FOOT_ROW)) > 0 then left = x break end
  end
  -- top-left position on the canvas that puts this pose's feet on the anchor
  return img, Point(AX - BACK_TO_ANCHOR - left, AY - img.height + 1)
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

local stance, stancePos = load("hp_1.png")
local windup, windupPos = load("hp_2.png")
local half, halfPos = load("hp_3b.png")
local punch, punchPos = load("hp_3.png")

-- idle: breathing, upper body sinks and rises over planted legs
local legsImg, upperImg = part(stance, WAIST, stance.height), part(stance, 0, WAIST)
local bob = { 0, 0, 1, 1, 2, 2, 1, 1 }
local n = 0
local function frame(dur)
  n = n + 1
  if n > 1 then spr:newEmptyFrame() end
  local f = spr.frames[n]
  f.duration = dur
  return f
end
for _, dy in ipairs(bob) do
  local f = frame(1 / 15)
  spr:newCel(legs, f, legsImg, stancePos)
  spr:newCel(upper, f, upperImg, Point(stancePos.x, stancePos.y + dy))
end
local idleEnd = n

-- st_hp (8 startup, 4 active, 20 recovery game frames = 8 steps of 1/15 s):
-- wind-up, half, PUNCH (active), hold, half back, settle into stance
local first = n + 1
local seq = {
  { windup, windupPos, 1 }, { half, halfPos, 1 }, { punch, punchPos, 3 },
  { half, halfPos, 2 }, { stance, stancePos, 1 },
}
for _, s in ipairs(seq) do
  local f = frame(s[3] / 15)
  spr:newCel(upper, f, s[1], s[2])
end
-- tags last: frames added after a tag would stretch it
spr:newTag(1, idleEnd).name = "idle"
spr:newTag(first, n).name = "st_hp"

-- shared palette, indexed like a real 16-bit sprite
app.command.ColorQuantization{ ui = false, withAlpha = false, maxColors = 48, useRange = false }
app.command.ChangePixelFormat{ format = "indexed", dithering = "none" }

local s = spr:newSlice(Rectangle(AX, AY, 1, 1))
s.name = "feet"

spr:saveAs(out)
