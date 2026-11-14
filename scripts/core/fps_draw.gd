extends Node2D
## FPS counter in the bottom-right corner (Settings "SHOW FPS").


func _process(_delta: float) -> void:
	visible = bool(Settings.v["show_fps"])
	if visible:
		queue_redraw()


func _draw() -> void:
	var txt := "%d FPS" % Engine.get_frames_per_second()
	var w := PixelFont.width(txt, 1)
	draw_rect(Rect2(380 - w - 2, 196, w + 4, 10), Color(0, 0, 0, 0.6))
	PixelFont.draw(self, txt, Vector2(380 - w, 198), 1, Color("80ff80"), Color("0a0a20"))
