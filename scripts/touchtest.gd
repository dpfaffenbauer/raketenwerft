extends Node
## Touch-Test für die Baukasten-Liste: wischen muss scrollen (ohne Teile zu ändern),
## antippen muss weiterhin den Knopf auslösen.  Start: Godot --path . -- --touchtest
## Mit "emulate_touch_from_mouse" verhält sich die Maus wie ein Finger am iPad.

var main
var ok := true

func _ready() -> void:
	Input.emulate_touch_from_mouse = true
	await get_tree().create_timer(1.0).timeout
	main.open_hangar(1)
	await _frames(20)
	var sc: ScrollContainer = main.ui.rows_box.get_parent()
	var bar := sc.get_v_scroll_bar()
	print("TOUCH liste max=%d sichtbar=%d" % [bar.max_value, bar.page])
	if bar.max_value <= bar.page:
		print("TOUCH Liste passt ganz aufs Bild, kein Scrollen nötig")
	# 1) Wischen, das auf einem Plus-Knopf beginnt
	var plus := _plus(1)
	var before := JSON.stringify(main.design)
	var swipe_hits := [0]
	plus.pressed.connect(func(): swipe_hits[0] += 1)
	var p := plus.get_global_rect().get_center()
	await _drag(p, p + Vector2(0, -260))
	await _frames(30)
	var scrolled := sc.scroll_vertical
	var changed: bool = JSON.stringify(main.design) != before or swipe_hits[0] > 0
	print("TOUCH wischen: gescrollt=%d  Knopf ausgelöst=%s" % [scrolled, changed])
	if scrolled <= 0 and bar.max_value > bar.page: ok = false
	if changed: ok = false
	# 2) Wischen, das auf der Beschriftung einer Zeile beginnt (zurück nach oben)
	var lab := _row(2).get_child(0).get_child(0) as Control
	var q := lab.get_global_rect().get_center()
	await _drag(q, q + Vector2(0, 260))
	await _frames(30)
	print("TOUCH zurückwischen: scroll=%d" % sc.scroll_vertical)
	if sc.scroll_vertical >= scrolled and scrolled > 0: ok = false
	# 3) Antippen: Plus muss wirken
	await _frames(90)   # Liste ausgleiten lassen (Schwung vom Wischen)
	sc.scroll_vertical = 0
	await _frames(5)
	plus = _plus(1)
	var hits := [0]
	plus.pressed.connect(func(): hits[0] += 1)
	await _tap(plus.get_global_rect().get_center())
	await _frames(5)
	print("TOUCH antippen: Knopf ausgelöst=%d" % hits[0])
	if hits[0] != 1: ok = false
	print("TOUCHTEST ", "OK" if ok else "FEHLER")
	get_tree().quit(0 if ok else 1)

func _row(i: int) -> PanelContainer:
	var n := 0
	for c in main.ui.rows_box.get_children():
		if c is PanelContainer:
			if n == i: return c
			n += 1
	return null

func _plus(i: int) -> Button:
	return _row(i).get_child(0).get_child(3) as Button

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _btn(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = pos; e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)

func _move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos; e.relative = rel; e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)

func _drag(a: Vector2, b: Vector2) -> void:
	_btn(a, true); await _frames(2)
	var steps := 12
	var last := a
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		_move(p, p - last); last = p
		await _frames(1)
	_btn(b, false); await _frames(2)

func _tap(p: Vector2) -> void:
	_btn(p, true); await _frames(3); _btn(p, false); await _frames(2)
