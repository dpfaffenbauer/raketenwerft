extends Control
## Touch-Knöpfe fürs Cockpit (mehrere Finger gleichzeitig) + Kamera wischen / zoomen.

var ui
var buttons: Array = []     # {name, rect, label, kind: hold|tap, big}
var held := {}              # name -> true
var touches := {}           # index -> {btn, pos}
var map_rect := Rect2()
var _pinch_d := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func relayout(vs: Vector2, map_r: Rect2, nav_r: Rect2) -> void:
	map_rect = map_r
	var s := clampf(minf(vs.x, vs.y) / 760.0, 0.8, 1.35)
	var b := 74.0 * s
	var g := 10.0 * s
	var lx := nav_r.position.x + nav_r.size.x + g * 2.0
	var by := vs.y - b - 14.0
	buttons = [
		{"name": "left", "rect": Rect2(lx, by, b, b), "label": "◀", "kind": "hold"},
		{"name": "right", "rect": Rect2(lx + b + g, by, b, b), "label": "▶", "kind": "hold"},
		{"name": "down", "rect": Rect2(lx, by - b - g, b, b), "label": "Zurück", "kind": "hold"},
		{"name": "up", "rect": Rect2(lx + b + g, by - b - g, b, b), "label": "Vor", "kind": "hold"},
	]
	var rx := map_r.position.x - g * 2.0 - b * 1.5 if map_r.size.x < vs.x * 0.5 else vs.x - b * 1.6 - 14.0
	var ry := vs.y - b * 1.5 - 14.0
	buttons.append({"name": "fire", "rect": Rect2(rx, ry, b * 1.5, b * 1.5), "label": "MOTOR", "kind": "hold", "big": true})
	buttons.append({"name": "warp", "rect": Rect2(rx - b - g, ry + b * 0.5, b, b), "label": "⏩", "kind": "hold"})
	buttons.append({"name": "stage", "rect": Rect2(rx, ry - b - g, b * 1.5, b * 0.8), "label": "Stufe ab", "kind": "tap"})
	buttons.append({"name": "cam", "rect": Rect2(rx - b - g, ry - b * 0.6 - g, b, b * 0.8), "label": "Kamera", "kind": "tap"})
	buttons.append({"name": "auto", "rect": Rect2(rx - b - g, ry - b * 1.4 - g * 2.0, b, b * 0.8), "label": "Computer", "kind": "tap"})
	buttons.append({"name": "sci", "rect": Rect2(rx, ry - b * 1.8 - g * 2.0, b * 1.5, b * 0.8), "label": "🔬 Wissen", "kind": "tap"})

func _hit(p: Vector2) -> String:
	for bt in buttons:
		if bt.rect.grow(6).has_point(p):
			return bt.name
	if map_rect.has_point(p):
		return "map"
	return ""

func _press(index: int, p: Vector2) -> bool:
	var n := _hit(p)
	touches[index] = {"btn": n, "pos": p}
	if n == "":
		return false
	if n == "map":
		ui.toggle_map()
	else:
		var kind := "hold"
		for bt in buttons:
			if bt.name == n:
				kind = bt.kind
		if kind == "hold":
			held[n] = true
		ui.main.touch_tap(n)
	return true

func _release(index: int) -> void:
	if touches.has(index):
		var n: String = touches[index].btn
		if n != "":
			var still := false
			for k in touches:
				if k != index and touches[k].btn == n:
					still = true
			if not still:
				held.erase(n)
		touches.erase(index)

func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if _press(e.index, e.position):
				get_viewport().set_input_as_handled()
		else:
			_release(e.index)
		_pinch_d = 0.0
	elif e is InputEventScreenDrag:
		if touches.has(e.index) and touches[e.index].btn == "":
			var cam_t := []
			for k in touches:
				if touches[k].btn == "":
					cam_t.append(k)
			touches[e.index].pos = e.position
			if cam_t.size() >= 2:
				var d: float = (touches[cam_t[0]].pos as Vector2).distance_to(touches[cam_t[1]].pos)
				if _pinch_d > 0.0:
					ui.main.cam_zoom(_pinch_d / maxf(d, 1.0))
				_pinch_d = d
			else:
				ui.main.cam_drag(e.relative)
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if _press(-1, e.position):
					get_viewport().set_input_as_handled()
			else:
				_release(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			ui.main.cam_zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			ui.main.cam_zoom(1.1)
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		if touches.has(-1) and touches[-1].btn == "" and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			ui.main.cam_drag(e.relative)
	elif e is InputEventMagnifyGesture:
		ui.main.cam_zoom(1.0 / e.factor)

func _draw() -> void:
	var font: Font = ui.font
	for bt in buttons:
		var r: Rect2 = bt.rect
		var on: bool = held.has(bt.name)
		var big: bool = bt.get("big", false)
		var col := Color(1.0, 0.82, 0.25, 0.95 if on else 0.82) if big else Color(1.0, 0.97, 0.93, 0.92 if on else 0.62)
		if on:
			col = col.darkened(0.15)
		var sb := StyleBoxFlat.new(); sb.bg_color = col; sb.set_corner_radius_all(int(r.size.y * 0.5) if big else 18)
		sb.shadow_color = Color(0, 0, 0, 0.3); sb.shadow_offset = Vector2(0, 4 if not on else 1)
		draw_style_box(sb, r)
		var label: String = preload("res://scripts/lang.gd").t(bt.label)   # Beschriftung in der eingestellten Sprache
		var fs := int(r.size.y * (0.22 if big else 0.3))
		fs = mini(fs, int(r.size.x / maxf(1.0, label.length()) * 1.7))
		if bt.label in ["◀", "▶", "⏩"]:
			fs = int(r.size.y * 0.42)
		draw_string(font, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(0.11, 0.16, 0.27))
