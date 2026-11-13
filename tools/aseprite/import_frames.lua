-- Adds a folder of frames (from tools/mixamo_move.py, or any other source) to a character's
-- .aseprite file as one tag, lined up on the 'feet' slice. Re-running replaces the tag.
-- Run: Aseprite.exe -b --script-param file=art/ced/ced.aseprite
--        --script-param dir=art/ced/moves/flying_knee --script-param tag=flying_knee
--        --script-param ax=52 --script-param ay=127 --script-param count=17 --script tools/aseprite/import_frames.lua
-- (ax, ay) = feet anchor inside the frames. Frames last 1/15 s each.
local p = app.params
local spr = app.open(p.file)
local count, ax, ay = tonumber(p.count), tonumber(p.ax), tonumber(p.ay)
local LAYER = "imported"

local feet
for _, s in ipairs(spr.slices) do if s.name == "feet" then feet = s end end
local fx, fy = feet.bounds.x, feet.bounds.y

-- drop an earlier import of this tag
for _, t in ipairs(spr.tags) do
  if t.name == p.tag then
    local from, to = t.fromFrame.frameNumber, t.toFrame.frameNumber
    spr:deleteTag(t)
    for i = to, from, -1 do spr:deleteFrame(spr.frames[i]) end
    break
  end
end

local layer
for _, l in ipairs(spr.layers) do if l.name == LAYER then layer = l end end
if not layer then
  layer = spr:newLayer()
  layer.name = LAYER
end

-- grow the canvas if the new frames reach past it, keeping everything else in place
local img0 = Image{ fromFile = p.dir .. "/f_00.png" }
local left, top = fx - ax, fy - ay
local gl, gt = math.max(0, -left), math.max(0, -top)
local gr = math.max(0, left + img0.width - spr.width)
local gb = math.max(0, top + img0.height - spr.height)
if gl + gt + gr + gb > 0 then
  spr:crop(Rectangle(-gl, -gt, spr.width + gl + gr, spr.height + gt + gb))  -- moves cels and slices too
  fx, fy = fx + gl, fy + gt
  left, top = left + gl, top + gt
end

-- appending frames right after a tag stretches that tag in Aseprite: remember the ranges
local ranges = {}
for _, t in ipairs(spr.tags) do ranges[t] = { t.fromFrame.frameNumber, t.toFrame.frameNumber } end
-- the sprite may be indexed: map every pixel to the nearest palette colour
local pal = spr.palettes[1]
local cache = {}
local function toSprite(img)
  if spr.colorMode ~= ColorMode.INDEXED then return img end
  local out = Image(img.width, img.height, ColorMode.INDEXED)
  out:clear(spr.transparentColor)
  local pc = app.pixelColor
  for it in img:pixels() do
    local v = it()
    if pc.rgbaA(v) >= 128 then
      local r, g, b = pc.rgbaR(v), pc.rgbaG(v), pc.rgbaB(v)
      local key = r * 65536 + g * 256 + b
      local idx = cache[key]
      if not idx then
        local best = math.huge
        for i = 0, #pal - 1 do
          if i ~= spr.transparentColor then
            local c = pal:getColor(i)
            local d = (c.red - r) ^ 2 + (c.green - g) ^ 2 + (c.blue - b) ^ 2
            if d < best then best, idx = d, i end
          end
        end
        cache[key] = idx
      end
      out:drawPixel(it.x, it.y, idx)
    end
  end
  return out
end

local first = #spr.frames + 1
for i = 0, count - 1 do
  local f = spr:newEmptyFrame(#spr.frames + 1)
  f.duration = 1 / 15
  local img = toSprite(Image{ fromFile = string.format("%s/f_%02d.png", p.dir, i) })
  spr:newCel(layer, f, img, Point(left, top))
end
for t, r in pairs(ranges) do
  t.fromFrame = spr.frames[r[1]]
  t.toFrame = spr.frames[r[2]]
end
local tag = spr:newTag(first, #spr.frames)
tag.name = p.tag
spr:saveAs(p.file)
print("imported " .. count .. " frames as '" .. p.tag .. "' at frame " .. first .. ", canvas " .. spr.width .. "x" .. spr.height)
