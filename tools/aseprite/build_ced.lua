-- Builds art/ced/ced.aseprite from the cut-out key poses (tools/aseprite/cutout_keys.py).
-- Run: Aseprite.exe -b --script-param dir=art/ced/keys --script-param out=art/ced/ced.aseprite --script tools/aseprite/build_ced.lua
-- Poses are lined up by the back foot, so the feet stay planted between frames.
local dir = app.params["dir"]
local out = app.params["out"]
local W, H = 140, 118
local AX, AY = 56, 114    -- feet anchor on the canvas (soles land on AY); room on the left for the sweep's hand
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

-- crouching poses (cr_hk sheet): lined up by the planted (back) boot, whose left edge is
-- measured per pose on row POSE_H - 4 (the hand on the floor would fool load()). The
-- crouch's feet are centred on the anchor; the sweep pivots on that boot.
local CR_PLANT = 23   -- planted boot's left edge -> anchor (measured on the 92 px keys)
local function loadAt(name, plantLeft)
  local img = Image{ fromFile = dir .. "/" .. name }
  return img, Point(AX - CR_PLANT - plantLeft, AY - img.height + 1)
end
local crouch, crouchPos = loadAt("cr_hk_2.png", 3)
local sweepIn, sweepInPos = loadAt("cr_hk_3.png", 26)
local sweep, sweepPos = loadAt("cr_hk_4.png", 27)
local sweepOut, sweepOutPos = loadAt("cr_hk_5.png", 19)

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
local hpEnd = n

-- crouch: one held frame
spr:newCel(upper, frame(1 / 15), crouch, crouchPos)
local crouchAt = n

-- cr_hk (9 startup, 3 active, 24 recovery = 9 steps): the sweep must be on screen by
-- game frame 9, so only 2 steps before it (2 * 36/9 = 8 <= 9)
local crFirst = n + 1
local crSeq = {
  { sweepIn, sweepInPos, 2 }, { sweep, sweepPos, 3 }, { sweepOut, sweepOutPos, 2 },
  { crouch, crouchPos, 2 },
}
for _, s in ipairs(crSeq) do
  local f = frame(s[3] / 15)
  spr:newCel(upper, f, s[1], s[2])
end
local crEnd = n

-- walk (walk sheet): weight first, then the free foot moves. 1 stance, 2 back foot up,
-- 3 feet together, 4 front foot up, 5 front foot reaching. The guard is the same in every
-- pose, so the poses are lined up by the head (left edge of its top rows) on the idle
-- stance's head: the body glides at the sim's walk speed and the legs step under it.
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
spr:newTag(crouchAt, crouchAt).name = "crouch"
spr:newTag(crFirst, crEnd).name = "cr_hk"
spr:newTag(wfFirst, wfEnd).name = "walk_f"
spr:newTag(wbFirst, n).name = "walk_b"

-- shared palette, indexed like a real 16-bit sprite
app.command.ColorQuantization{ ui = false, withAlpha = false, maxColors = 48, useRange = false }
app.command.ChangePixelFormat{ format = "indexed", dithering = "none" }

local s = spr:newSlice(Rectangle(AX, AY, 1, 1))
s.name = "feet"

spr:saveAs(out)
