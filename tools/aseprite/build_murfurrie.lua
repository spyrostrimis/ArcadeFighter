-- Builds art/murfurrie/murfurrie.aseprite from the cut-out key poses (tools/aseprite/cutout_keys.py,
-- then tools/aseprite/hue_shift.py for the light blue suit; see docs/move_workflow.md).
-- Run: Aseprite.exe -b --script-param dir=art/murfurrie/keys --script-param out=art/murfurrie/murfurrie.aseprite --script tools/aseprite/build_murfurrie.lua
-- Same layout as build_ced.lua: poses lined up by the back foot, so the feet stay planted.
local dir = app.params["dir"]
local out = app.params["out"]
local W, H = 140, 118
local AX, AY = 56, 114    -- feet anchor on the canvas (soles land on AY)
-- Murfurrie's stance has CED's proportions: same measurements, scaled from the 113 px stance
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

local n = 0
local function frame(dur)
  n = n + 1
  if n > 1 then spr:newEmptyFrame() end
  local f = spr.frames[n]
  f.duration = dur
  return f
end

-- idle: breathing, upper body sinks and rises over planted legs
local legsImg, upperImg = part(stance, WAIST, stance.height), part(stance, 0, WAIST)
for _, dy in ipairs({ 0, 0, 1, 1, 2, 2, 1, 1 }) do
  local f = frame(1 / 15)
  spr:newCel(legs, f, legsImg, stancePos)
  spr:newCel(upper, f, upperImg, Point(stancePos.x, stancePos.y + dy))
end
local idleEnd = n

-- st_hp (8 startup, 4 active, 16 recovery game frames = 7 steps of 1/15 s):
-- wind-up, half, PUNCH (active), half back, settle into stance
local first = n + 1
for _, s in ipairs({
  { windup, windupPos, 1 }, { half, halfPos, 1 }, { punch, punchPos, 3 },
  { half, halfPos, 1 }, { stance, stancePos, 1 },
}) do
  spr:newCel(upper, frame(s[3] / 15), s[1], s[2])
end
local hpEnd = n

-- spit (13 startup, 4 active, 26 recovery = 11 steps): rears back (upper body back and up,
-- breathing in), then lunges the head forward (the wind-up pose) and spits; the projectile
-- leaves on the first active frame. The lunge isn't the widest frame, so the tag names its
-- hit frame in its user data ("hit:<frame in tag>"; export.py passes it to the game).
local spFirst = n + 1
for _, s in ipairs({ { -1, 0, 1 }, { -2, -1, 2 } }) do   -- dx, dy, steps
  local f = frame(s[3] / 15)
  spr:newCel(legs, f, legsImg, stancePos)
  spr:newCel(upper, f, upperImg, Point(stancePos.x + s[1], stancePos.y + s[2]))
end
spr:newCel(upper, frame(3 / 15), windup, windupPos)       -- the spit (hit frame: 3rd of the tag)
spr:newCel(upper, frame(3 / 15), windup, windupPos)
spr:newCel(upper, frame(2 / 15), stance, stancePos)
local spEnd = n

-- walk (walk sheet, like build_ced.lua): 1 stance, 2 back foot up, 3 feet together,
-- 4 foot up, 5 front foot reaching. Lined up by the head (left edge of its top rows) on the
-- idle stance's head: the body glides at the sim's walk speed and the legs step under it.
-- Looping animations play one frame per step; walk_b is the same cycle backwards.
local function headLeft(img)
  for x = 0, img.width - 1 do
    for y = 0, 11 do
      if app.pixelColor.rgbaA(img:getPixel(x, y)) > 0 then return x end
    end
  end
  return 0
end
local stanceHead = stancePos.x + headLeft(stance)
local walk = {}
for i = 1, 5 do
  local img = Image{ fromFile = dir .. "/walk_" .. i .. ".png" }
  walk[i] = { img, Point(stanceHead - headLeft(img), AY - img.height + 1) }
end
local function walkCycle(order)
  local from = n + 1
  for _, i in ipairs(order) do spr:newCel(upper, frame(1 / 15), walk[i][1], walk[i][2]) end
  return from
end
local wfFirst = walkCycle({ 1, 2, 3, 4, 5 })
local wfEnd = n
local wbFirst = walkCycle({ 5, 4, 3, 2, 1 })

-- tags last: frames added after a tag would stretch it
spr:newTag(1, idleEnd).name = "idle"
spr:newTag(first, hpEnd).name = "st_hp"
local spTag = spr:newTag(spFirst, spEnd)
spTag.name = "spit"
spTag.data = "hit:2"
spr:newTag(wfFirst, wfEnd).name = "walk_f"
spr:newTag(wbFirst, n).name = "walk_b"

-- shared palette, indexed like a real 16-bit sprite
app.command.ColorQuantization{ ui = false, withAlpha = false, maxColors = 48, useRange = false }
app.command.ChangePixelFormat{ format = "indexed", dithering = "none" }

local s = spr:newSlice(Rectangle(AX, AY, 1, 1))
s.name = "feet"

spr:saveAs(out)
