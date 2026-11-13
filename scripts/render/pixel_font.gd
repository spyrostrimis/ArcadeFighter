class_name PixelFont
## Tiny 5x7 bitmap font drawn with rects, so text stays crisp at 384x216.
## Supports scaling, italics, bold, outline and vertical colour gradients.

const W := 5
const H := 7

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	"-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
	":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
	"'": ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
	"<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
	"(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
	")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


static func width(text: String, scale := 1, bold := false) -> int:
	if text.is_empty():
		return 0
	var adv := (W + 1) * scale + (1 if bold else 0)
	return text.length() * adv - scale


static func height(scale := 1) -> int:
	return H * scale


## Draws text with top-left at pos. colors: one Color or an Array gradient (top->bottom).
static func draw(ci: CanvasItem, text: String, pos: Vector2, scale := 1, colors: Variant = Color.WHITE,
		outline: Variant = null, italic := 0, bold := false, outline_w := 1) -> void:
	var grad: Array = colors if colors is Array else [colors]
	var adv := (W + 1) * scale + (1 if bold else 0)
	var bw := scale + (1 if bold else 0)
	var total_h := H * scale
	var ox := int(pos.x)
	var oy := int(pos.y)
	if outline != null:
		var oc: Color = outline
		_pass(ci, text, ox, oy, scale, adv, bw, italic, total_h, [oc], outline_w)
	_pass(ci, text, ox, oy, scale, adv, bw, italic, total_h, grad, 0)


static func draw_centered(ci: CanvasItem, text: String, center_x: float, y: float, scale := 1,
		colors: Variant = Color.WHITE, outline: Variant = null, italic := 0, bold := false, outline_w := 1) -> void:
	var w := width(text, scale, bold)
	draw(ci, text, Vector2(int(center_x - w / 2.0), y), scale, colors, outline, italic, bold, outline_w)


static func _pass(ci: CanvasItem, text: String, ox: int, oy: int, scale: int, adv: int, bw: int,
		italic: int, total_h: int, grad: Array, grow: int) -> void:
	var cx := ox
	for ch in text.to_upper():
		var g: Array = GLYPHS.get(ch, GLYPHS["?"])
		for row in H:
			var line: String = g[row]
			for sub in scale:
				var py := row * scale + sub
				var shift := 0
				if italic > 0:
					shift = int((total_h - py) * italic / (total_h * 1.0) * scale)
				var col: Color = grad[clampi(py * grad.size() / total_h, 0, grad.size() - 1)]
				var run_start := -1
				for c in W + 1:
					var on := c < W and line[c] == "#"
					if on and run_start < 0:
						run_start = c
					elif not on and run_start >= 0:
						var x0 := cx + run_start * scale + shift - grow
						var x1 := cx + (c - 1) * scale + shift + bw + grow
						var te := 0
						var be := 0
						if grow > 0:
							te = grow if sub == 0 and _edge_top(g, row, run_start, c) else 0
							be = grow if sub == scale - 1 and _edge_bottom(g, row, run_start, c) else 0
						ci.draw_rect(Rect2(x0, oy + py - te, x1 - x0, 1 + te + be), col)
						run_start = -1
		cx += adv


static func _edge_top(g: Array, row: int, a: int, b: int) -> bool:
	if row == 0:
		return true
	var above: String = g[row - 1]
	for c in range(a, b):
		if above[c] != "#":
			return true
	return false


static func _edge_bottom(g: Array, row: int, a: int, b: int) -> bool:
	if row == H - 1:
		return true
	var below: String = g[row + 1]
	for c in range(a, b):
		if below[c] != "#":
			return true
	return false
