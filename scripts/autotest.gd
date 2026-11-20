extends Node
## Automatischer Testpilot. Start:
##   Godot --path . -- --autotest=orbit [--shots=/pfad] [--speed=4] [--lang=en] [--langswitch] [--showtouch]
## Fliegt die Mission wie ein Kind mit Knöpfen, schreibt Zustand ins Log,
## macht Bildschirmfotos (nur mit Fenster) und beendet sich mit Code 0 (geschafft) oder 1.

const P := preload("res://scripts/phys.gd")
const Missions := preload("res://scripts/missions.gd")

var main
var mission := ""
var shots := ""
var t := 0.0
var log_t := 0.0
var shot_n := 0
var shot_marks := {}
var hold := {}
var started := false
var done := false
var computer_only := false   # --computer: nur den Computer-Knopf drücken, sonst nichts
var show_touch := false      # --showtouch: Touch-Knöpfe auch ohne Touchscreen zeigen (für Fotos)
var lang_switch := false     # --langswitch: auf dem Titel per Taste L die Sprache wechseln (Foto) und zurück

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="): mission = a.substr(11)
		if a.begins_with("--shots="): shots = a.substr(8)
		if a.begins_with("--speed="): Engine.time_scale = float(a.substr(8))
		if a == "--computer": computer_only = true
		if a == "--langswitch": lang_switch = true
		if a == "--showtouch": show_touch = true
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	print("AUTOTEST ", mission)

func _shot(name: String) -> void:
	if shots == "" or shot_marks.has(name) or DisplayServer.get_name() == "headless":
		shot_marks[name] = true
		return
	shot_marks[name] = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s_%s.png" % [shots, shot_n, mission, name]); shot_n += 1

func _key(n: String, on: bool) -> void:
	if on: main.ui.touch.held[n] = true
	else: main.ui.touch.held.erase(n)

## Taste drücken und loslassen wie auf der Tastatur
func _press(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new(); e.keycode = k; e.pressed = down
		Input.parse_input_event(e)

func _tap(n: String) -> void:
	main.touch_tap(n)

func _state() -> Dictionary:
	var f = main.flight
	var o := {"t": snappedf(f.t, 0.1), "screen": main.screen, "warp": snappedf(f.warp, 0.1)}
	if f.M:
		o.phase = f.M.phase; o.asc = f.M.asc
	var v = f.vessel
	if v:
		var r: float = sqrt(v.x * v.x + v.y * v.y)
		var el := P.elements(v.x, v.y, v.vx, v.vy)
		o.alt = int(r - P.R); o.sp = int(sqrt(v.vx * v.vx + v.vy * v.vy)); o.s = v.s; o.thr = v.throttle; o.landed = v.landed; o.chute = v.chute
		o.heat = snappedf(v.heat, 0.01)
		if not el.esc:
			o.ap = int(el.ap); o.pe = int(el.pe)
	if f.pred.has("moon_min"):
		o.mmin = int(f.pred.moon_min - P.RMOON); o.back = f.pred.get("back", false); o.mhit = f.pred.has("moon_hit")
	if f.pred.has("impact"): o.imp_t = int(f.pred.impact.t - f.t)
	if f.iss and f.iss.dynamic:
		o.iss_alt = int(sqrt(f.iss.x * f.iss.x + f.iss.y * f.iss.y) - P.R)
	if f.pred.has("impact"):
		o.imp = int(rad_to_deg(f.pred.impact.phi))
	return o

func _process(dt: float) -> void:
	if mission == "" or done:
		return
	t += dt
	var f = main.flight
	if not started and t > 1.0:
		started = true
		main.ui.sci_on = true
		await _shot("title")   # erst das Titelbild fotografieren, dann zur Mission
		if lang_switch:
			_press(KEY_L)
			await get_tree().create_timer(0.5).timeout
			print("LANGSWITCH ", preload("res://scripts/lang.gd").current(), " ", main.ui.title_box.get_meta("lang_btn").text)
			await _shot("title_lang")
			_press(KEY_L)
			await get_tree().create_timer(0.3).timeout
			print("LANGSWITCH ", preload("res://scripts/lang.gd").current(), " ", main.ui.title_box.get_meta("lang_btn").text)
		var idx := 0
		for i in Missions.LIST.size():
			if Missions.LIST[i].id == mission: idx = i
		main.begin_mission(idx)
		return
	if not started:
		return
	if main.screen == "hangar":
		_shot("hangar")
		if t > 3.0:
			var need: String = Missions.LIST[main.hangar_mission].need
			main.hangar_preset("moon" if need == "moon" else ("orbit" if need == "orbit" else "hop"))   # immer die passende Standard-Rakete
			main.hangar_warned = true
			main.hangar_launch()
		return
	if main.screen == "result":
		_shot("result")
		print("RESULT ", main.ui.get_meta("ok", false), " ", main.ui.r_title.text)
		done = true
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit(0 if main.ui.get_meta("ok", false) else 1))
		return
	if main.screen != "flight" or f.M == null:
		return
	if show_touch: main.ui.touch.visible = true
	log_t -= dt
	if log_t <= 0.0:
		log_t = 2.0 / Engine.time_scale
		print("STATE ", JSON.stringify(_state()))
	if t > (3000.0 if mission == "moon" else 1500.0):
		print("TIMEOUT"); done = true; get_tree().quit(2); return
	var M = f.M
	var v = f.vessel
	var st := _state()
	# Piloten-Logik
	for n in ["fire", "warp", "left", "right", "up", "down"]:
		hold[n] = false
	if M.phase == "count" and f.countdown < 1.5: _shot("startplatz")
	if st.get("alt", 0) > 40 and st.get("alt", 0) < 400: _shot("abheben")
	match mission:
		"hop":
			if M.phase == "pad": _tap("fire")
			elif v and not v.capsule_only() and not v.all_empty(): hold.fire = true
			elif st.get("alt", 0) > P.ATM + 500: hold.warp = true
			if st.get("alt", 0) > 2000: _shot("hoch")
			if v and v.chute: _shot("fallschirm")
		"orbit", "moon", "free":
			if M.phase == "pad" and not f.auto: _tap("auto")
			if computer_only:
				if st.get("alt", 0) > 800: _shot("aufstieg")
				if M.asc == "orbit": _shot("orbit")
				if mission == "moon" and M.phase == "coast" and M.S.has("near"): _shot("mond")
				if mission == "moon" and v and v.heat > 0.4: _shot("gluehen")
				for n in hold: _key(n, false)
				return
			if M.asc == "coast": hold.warp = true
			if st.get("alt", 0) > 800: _shot("aufstieg")
			if M.asc == "orbit": _shot("orbit")
			if mission == "moon" and M.asc == "orbit":
				match M.phase:
					"wait", "coast", "return":
						hold.warp = not (M.phase == "return" and st.get("alt", 999999) < 7000)
					"tli", "fix":
						hold.fire = true
				if M.phase == "coast" and M.S.has("near"): _shot("mond")
				if v and v.heat > 0.4: _shot("gluehen")
		"home":
			if M.phase == "intro" and f.sas != "retro": _tap("down")
			if M.phase == "burn": hold.fire = true
			if M.phase == "fall" and st.get("alt", 0) > 6500 and not v.landed: hold.warp = true
			if v and v.heat > 0.4: _shot("gluehen")
			if v and v.chute: _shot("fallschirm")
		"iss":
			if M.phase == "turn":
				if f.sas != "retro": _tap("down")
				else: hold.fire = true
			if M.phase == "chase": hold.warp = true
			if not f.dock.is_empty() and not f.dock.done:
				_shot("andocken")
				var rel: Vector3 = f.dock.rel
				hold.left = rel.x > 0.3; hold.right = rel.x < -0.3
				hold.down = rel.y > 0.3; hold.up = rel.y < -0.3
				hold.fire = absf(rel.x) < 0.5 and absf(rel.y) < 0.5
		"issd":
			if M.phase == "decay": hold.warp = true
			if M.phase == "burn":
				_shot("bremsschiff")
				var phi := fposmod(atan2(f.iss.y, f.iss.x), TAU)
				var at_mark: bool = absf(P.ang_diff(phi, Missions.NEMO_BURN)) < 0.06 or M.S.has("burning")
				if at_mark and not M.in_zone():
					hold.fire = true; M.S.burning = true
				elif not at_mark:
					hold.warp = true
			if M.phase == "fall": hold.warp = true
			if M.phase == "air": _shot("gluehen")
			if M.phase == "pieces": _shot("truemmer")
	for n in hold:
		_key(n, hold[n])
