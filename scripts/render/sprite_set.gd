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
func draw_frame(ci: CanvasItem, anim: String, index: int) -> void:
	var a: Dictionary = anims[anim]
	var frames: Array = a["frames"]
	var i := posmod(index, frames.size())
	var r: Rect2 = frames[i]
	var anchor: Vector2 = a["anchors"][i]
	ci.draw_texture_rect_region(tex, Rect2(-anchor, r.size), r)


func frame_count(anim: String) -> int:
	return (anims[anim]["frames"] as Array).size()
