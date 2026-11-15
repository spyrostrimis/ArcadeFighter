class_name SpriteSet
extends RefCounted
## A character's sprite sheet + animation data produced by tools/pixelize.py.
## assets/fighters/<id>/<id>.png and <id>.json

var tex: Texture2D
var fps := 15.0
var anims := {}   # name -> {"frames": Array[Rect2], "anchors": Array[Vector2]} (anchor = feet, in frame space)

static var _cache := {}


static func load_for(cid: String) -> SpriteSet:
	if _cache.has(cid):
		return _cache[cid]
	var base := "res://assets/fighters/%s/%s" % [cid, cid]
	var s: SpriteSet = null
	if ResourceLoader.exists(base + ".png") and FileAccess.file_exists(base + ".json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		if data is Dictionary:
			s = SpriteSet.new()
			s.tex = load(base + ".png")
			s.fps = float(data.get("fps", 15.0))
			for name in data["animations"]:
				var a: Dictionary = data["animations"][name]
				var frames: Array[Rect2] = []
				var anchors: Array[Vector2] = []
				for fr in a["frames"]:
					frames.append(Rect2(fr[0], fr[1], fr[2], fr[3]))
					# Aseprite export: [x, y, w, h, ax, ay]; old pixelize.py export: one anchor per anim
					anchors.append(Vector2(fr[4], fr[5]) if fr.size() >= 6 else Vector2(a["anchor"][0], a["anchor"][1]))
				s.anims[name] = {"frames": frames, "anchors": anchors}
	_cache[cid] = s
	return s


func has(anim: String) -> bool:
	return anims.has(anim)


## Draws frame `index` of `anim` with its feet anchor at the canvas origin.
func draw_frame(ci: CanvasItem, anim: String, index: int, modulate := Color.WHITE) -> void:
	var a: Dictionary = anims[anim]
	var frames: Array = a["frames"]
	var i := posmod(index, frames.size())
	var r: Rect2 = frames[i]
	var anchor: Vector2 = a["anchors"][i]
	ci.draw_texture_rect_region(tex, Rect2(-anchor, r.size), r, modulate)


## Frames the hit pose stays up after the last active frame (so the impact reads).
const HIT_HOLD := 2


## [first, last] index of an attack's hit pose: its widest (most extended) frames.
func hit_span(anim: String) -> Vector2i:
	var a: Dictionary = anims[anim]
	if not a.has("hit"):
		var frames: Array = a["frames"]
		var w := 0.0
		for r in frames:
			w = maxf(w, (r as Rect2).size.x)
		var first := -1
		var last := -1
		for i in frames.size():
			if (frames[i] as Rect2).size.x == w:
				if first < 0:
					first = i
				last = i
			elif first >= 0:
				break
		a["hit"] = Vector2i(first, last)
	return a["hit"]


## Attack frame synced to the move's frame data: the wind-up frames during startup, the hit
## pose from the first active frame until HIT_HOLD frames after the last, the rest of the
## frames (pulling back) during recovery. Even spreading over the whole move left the limb
## out long after the hit and made long moves (sweeps) feel slow.
func attack_index(anim: String, sf: int, startup: int, active: int, total: int) -> int:
	var n := frame_count(anim)
	var h := hit_span(anim)
	var hold_end := mini(total, startup + active + HIT_HOLD)
	if sf < startup:
		return clampi(sf * h.x / maxi(1, startup), 0, maxi(0, h.x - 1))
	if sf < hold_end:
		return h.x + (sf - startup) * (h.y - h.x + 1) / maxi(1, hold_end - startup)
	var rest := n - 1 - h.y
	if rest <= 0:
		return h.y
	return h.y + 1 + mini(rest - 1, (sf - hold_end) * rest / maxi(1, total - hold_end))


func frame_count(anim: String) -> int:
	return (anims[anim]["frames"] as Array).size()
