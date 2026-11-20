extends Node
## Pauls Raketenwerft – Hauptablauf: Titel, Werft, Flug, Ergebnis.

const P := preload("res://scripts/phys.gd")
const Parts := preload("res://scripts/parts.gd")
const Missions := preload("res://scripts/missions.gd")
const W := preload("res://scripts/world.gd")
const L := preload("res://scripts/lines.gd")
const T := preload("res://scripts/lang.gd")

var world: Node3D
var flight: Node3D
var cam: Camera3D
var audio: Node
var ui: CanvasLayer
var hangar: Node3D
var hangar_rocket: Node3D
var hangar_spin := 0.0

var screen := ""
var title_sel := 0
var progress := {"done": {}, "design": {}}
var design := {}
var hangar_mission := 0
var hangar_sel := 1
var hangar_warned := false
var hints_said := {}
var touch_taps := {}
var title_a := 0.0
var last_mission := 0
var last_design := {}
var hangar_ready_lights := false

func _log_fps() -> void:
	var f := FileAccess.open("user://fps.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://fps.log") else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%d %s %s" % [Engine.get_frames_per_second(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()])

func _ready() -> void:
	if OS.has_feature("simulator"):   # Messwert für Tests: Bilder pro Sekunde + Renderer -> user://fps.log
		var t := Timer.new(); t.wait_time = 3.0; t.autostart = true; add_child(t)
		t.timeout.connect(_log_fps)
	_load_progress()
	audio = preload("res://scripts/audio.gd").new(); add_child(audio)
	world = preload("res://scripts/world.gd").new(); add_child(world)
	cam = Camera3D.new(); cam.fov = 55.0; cam.near = 0.3; cam.far = 3.0e6; add_child(cam); cam.make_current()
	flight = preload("res://scripts/flight.gd").new(); flight.main = self; flight.world = world; flight.cam = cam; add_child(flight)
	ui = preload("res://scripts/ui.gd").new(); ui.main = self; add_child(ui)
	_build_hangar()
	show_title()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			var at = preload("res://scripts/autotest.gd").new(); at.main = self; add_child(at)
		if a == "--touchtest":
			var tt = preload("res://scripts/touchtest.gd").new(); tt.main = self; add_child(tt)
	get_tree().create_timer(0.8).timeout.connect(_welcome)

func _welcome() -> void:
	if screen == "title":
		say("welcome")

# ---------- Fortschritt ----------
func _load_progress() -> void:
	if FileAccess.file_exists("user://progress.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://progress.json"))
		if d is Dictionary:
			progress.done = d.get("done", {})
			progress.design = _clean_design(d.get("design", {}))

## JSON liefert Zahlen als Kommazahlen – für Stufen brauchen wir ganze Zahlen
func _clean_design(d) -> Dictionary:
	if not (d is Dictionary) or not d.has("stages"):
		return {}
	var out := {"color": int(d.get("color", 0)), "stages": []}
	for s in d.stages:
		out.stages.append({"tanks": clampi(int(s.get("tanks", 1)), 1, 5), "engine": String(s.get("engine", "small")),
			"boosters": int(s.get("boosters", 0)), "fins": bool(s.get("fins", false))})
	return out

func _save_progress() -> void:
	var fa := FileAccess.open("user://progress.json", FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(progress))

func mark_done(id: String) -> void:
	progress.done[id] = true; _save_progress()

# ---------- Mira ----------
func say(id: String) -> void:
	ui.show_caption(L.text(id))
	audio.say(id)

# ---------- Bildschirme ----------
func _world_visible(on: bool) -> void:
	world.visible = on
	world.env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
	world.env.background_color = Color(0.03, 0.05, 0.11)
	world.env.ssr_enabled = not on
	world.env.volumetric_fog_enabled = false
	if title_paul:
		title_paul.visible = on and screen == "title"
	world.sun_light.visible = on
	hangar.visible = not on

func show_title() -> void:
	screen = "title"
	if title_paul:
		title_paul.visible = true
	flight.clear(); flight.active = false; flight.M = null; flight.paused = false
	_world_visible(true)
	ui.show_only("title"); ui.build_cards(progress.done, title_sel)
	audio.set_music("space"); audio.stop_voice()
	flight.t = 0.0; P.moon_theta0 = 1.2

func show_facts() -> void:
	screen = "facts"; ui.fill_facts(progress.done); ui.show_only("facts")

func begin_mission(i: int) -> void:
	title_sel = i
	if Missions.LIST[i].build:
		open_hangar(i)
	else:
		start_flight(i, {})

func start_flight(i: int, d: Dictionary) -> void:
	flight.clear()
	title_paul.visible = false
	_world_visible(true)
	last_mission = i; last_design = d.duplicate(true)
	var M = Missions.new(flight, self, i, d)
	flight.M = M; flight.active = true; flight.paused = false
	screen = "flight"; ui.show_only("flight"); ui.map_big = false; ui._place_map()
	ui.m_title.text = "%s %s" % [Missions.LIST[i].icon, T.t(Missions.LIST[i].title)]
	M.setup()
	ui.update_hud(flight)

func restart_mission() -> void:
	start_flight(last_mission, last_design)

func show_result(ok: bool, icon: String, title: String, facts_key: String, index: int) -> void:
	if screen != "flight":
		return
	screen = "result"
	ui.show_only("result")
	var facts: Array = Missions.FACTS.get(facts_key, []) if facts_key != "" else []
	ui.show_result(ok, icon, title, facts, index < Missions.LIST.size() - 1)
	ui.set_meta("ok", ok)
	if ok:
		audio.sfx("win")
		_confetti()
		if not audio.speaking():
			say("done")

func _confetti() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.explosiveness = 0.85; p.amount = 220; p.lifetime = 4.0; p.local_coords = false
	var bm := BoxMesh.new(); bm.size = Vector3(0.05, 0.08, 0.01)
	var m := StandardMaterial3D.new(); m.vertex_color_use_as_albedo = true; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.material = m; p.mesh = bm
	p.direction = Vector3(0, 1, 0); p.spread = 55.0; p.initial_velocity_min = 2.5; p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -2.5, 0); p.damping_min = 0.5; p.damping_max = 1.2
	p.angular_velocity_min = -400; p.angular_velocity_max = 400
	p.scale_amount_min = 0.7; p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.3, 0.35)); g.set_color(1, Color(0.3, 0.7, 1.0))
	g.add_point(0.25, Color(1, 0.82, 0.2)); g.add_point(0.5, Color(0.3, 0.9, 0.5)); g.add_point(0.75, Color(0.7, 0.4, 1.0))
	p.color_initial_ramp = g
	cam.add_child(p)
	p.position = Vector3(0, -1.6, -3.0)
	p.emitting = true
	get_tree().create_timer(5.0).timeout.connect(p.queue_free)

func result_next() -> void:
	var ok: bool = ui.get_meta("ok", false)
	if ok and last_mission < Missions.LIST.size() - 1:
		begin_mission(last_mission + 1)
	elif ok:
		show_title()
	else:
		restart_mission()

func toggle_pause(on: bool) -> void:
	if screen != "flight":
		return
	flight.paused = on
	ui.pause_box.visible = on
	if on:
		audio.engine(0, 0); audio.wind(0, 0)

# =====================================================================
#  Werft
# =====================================================================
const Toon := preload("res://scripts/toon.gd")
var hangar_paul: Node3D
var title_paul: Node3D

func _build_hangar() -> void:
	hangar = Node3D.new(); add_child(hangar)
	hangar.add_child(Toon.studio_backdrop())
	# glänzender Studioboden
	var floor_m := W.cyl(120, 120, 0.4, Toon.plastic(Color(0.62, 0.74, 0.95), 0.28, 0.5), 96); floor_m.position.y = -0.2; hangar.add_child(floor_m)
	var ring := Toon.torus(14.0, 15.2, Toon.plastic(Color(1.0, 0.82, 0.25), 0.3, 0.7)); ring.scale = Vector3(1, 0.25, 1); ring.position.y = 0.05; hangar.add_child(ring)
	var plate := W.cyl(8, 8.8, 0.9, Toon.plastic(Color(0.35, 0.55, 0.95), 0.3, 0.7), 64); plate.position.y = 0.45; plate.name = "Plate"; hangar.add_child(plate)
	var plate_top := W.cyl(7.6, 7.6, 0.12, Toon.plastic(Color(0.95, 0.97, 1.0), 0.25, 0.7), 64); plate_top.position.y = 0.95; plate.add_child(plate_top); plate_top.position = Vector3(0, 0.5, 0)
	# bunte Spielzeugkisten und Gerüst
	for c in [[-24, 12, Color(0.95, 0.3, 0.35), 4.5], [-27.5, 17, Color(1.0, 0.78, 0.2), 3.2], [23, 14, Color(0.3, 0.8, 0.5), 4.0], [27, 9, Color(0.55, 0.45, 0.95), 3.0]]:
		var crate := W.box(Vector3(c[3], c[3], c[3]), Toon.plastic(c[2], 0.35, 0.7)); crate.position = Vector3(c[0], c[3] / 2.0, c[1]); crate.rotation.y = c[0] * 0.1; hangar.add_child(crate)
	for xz in [[-13, -8], [13, -9]]:
		var tw := Toon.capsule(0.7, 60.0, Toon.plastic(Color(1.0, 0.82, 0.25), 0.35, 0.6)); tw.position = Vector3(xz[0], 30, xz[1]); hangar.add_child(tw)
	# Paul steht neben der Rakete
	hangar_paul = Toon.astronaut()
	hangar_paul.scale = Vector3.ONE * 4.2
	hangar_paul.position = Vector3(5.0, 1.0, 5.2); hangar_paul.rotation.y = 0.35
	hangar.add_child(hangar_paul)
	# Studiolicht: warmes Hauptlicht mit Schatten, kühles Kantenlicht, weiches Fülllicht
	var key := DirectionalLight3D.new(); key.light_energy = 1.3; key.light_color = Color(1.0, 0.95, 0.88); key.shadow_enabled = true
	key.directional_shadow_max_distance = 150.0; key.shadow_blur = 2.5
	hangar.add_child(key); key.set_meta("dir", Vector3(-0.5, -0.8, -0.6))
	var rim := DirectionalLight3D.new(); rim.light_energy = 0.9; rim.light_color = Color(0.7, 0.85, 1.0)
	hangar.add_child(rim); rim.set_meta("dir", Vector3(0.6, -0.2, 0.9))
	var fill := OmniLight3D.new(); fill.omni_range = 150; fill.light_energy = 0.8; fill.light_color = Color(0.9, 0.95, 1.0); fill.position = Vector3(10, 25, 40); hangar.add_child(fill)
	hangar.position = Vector3(0, 0, 5.0e5)
	hangar.visible = false
	hangar_ready_lights = true
	# Paul schwebt im Titelbild vor der Erde
	title_paul = Toon.astronaut()
	add_child(title_paul)

func _rows() -> Array:
	var rows := [{"k": "head", "label": T.t("Rakete")}, {"k": "count", "label": T.t("Anzahl Stufen")}]
	for i in range(design.stages.size() - 1, -1, -1):
		rows.append({"k": "head", "label": T.t("Stufe %d") % (i + 1) + (T.t(" (unten)") if i == 0 else "")})
		rows.append({"k": "tanks", "i": i, "label": T.t("⛽ Tanks")})
		rows.append({"k": "engine", "i": i, "label": T.t("🔥 Motor")})
		if i == 0:
			rows.append({"k": "boost", "i": i, "label": T.t("🚀 Booster")})
			rows.append({"k": "fins", "i": i, "label": T.t("🔺 Flossen")})
	rows.append({"k": "head", "label": T.t("Aussehen")})
	rows.append({"k": "color", "label": T.t("🎨 Farbe")})
	return rows

func _selectable() -> Array:
	return _rows().filter(func(r): return r.k != "head")

func _row_value(r: Dictionary) -> String:
	var s: Dictionary = design.stages[r.i] if r.has("i") else {}
	match r.k:
		"count": return str(design.stages.size())
		"tanks": return "▮".repeat(s.tanks)
		"engine": return T.t(Parts.ENGINES[s.engine].name)
		"boost": return (T.t("%d Stück") % s.get("boosters", 0)) if s.get("boosters", 0) > 0 else T.t("keine")
		"fins": return T.t("ja" if s.get("fins", false) else "nein")
		"color": return T.t(Parts.COLOR_NAMES[design.get("color", 0)])
	return ""

func _hint_once(id: String) -> void:
	if hints_said.has(id):
		return
	hints_said[id] = true; say(id)

func change_row(sel_idx: int, r: Dictionary, dir: int) -> void:
	hangar_sel = sel_idx
	var s: Dictionary = design.stages[r.i] if r.has("i") else {}
	match r.k:
		"count":
			if dir > 0 and design.stages.size() < 3:
				design.stages.append({"tanks": 1, "engine": "vac", "boosters": 0, "fins": false}); _hint_once("h_stage")
			elif dir < 0 and design.stages.size() > 1:
				design.stages.pop_back()
			else:
				return
		"tanks":
			var mx := 5 if r.i == 0 else 4
			var n := clampi(s.tanks + dir, 1, mx)
			if n == s.tanks:
				return
			s.tanks = n
			if dir > 0: _hint_once("h_tanks")
		"engine":
			var o := ["small", "big", "vac"]
			s.engine = o[(o.find(s.engine) + dir + 3) % 3]
		"boost":
			var o := [0, 2, 4]
			s.boosters = o[(o.find(s.get("boosters", 0)) + dir + 3) % 3]
			if s.boosters > 0: _hint_once("h_boost")
		"fins":
			s.fins = not s.get("fins", false)
		"color":
			design.color = (design.get("color", 0) + dir + Parts.COLOR_NAMES.size()) % Parts.COLOR_NAMES.size()
	audio.sfx("snap"); hangar_warned = false
	refresh_hangar(true)

func refresh_hangar(rebuild: bool) -> void:
	var rows := _rows()
	var sel := _selectable()
	hangar_sel = clampi(hangar_sel, 0, sel.size() - 1)
	ui.build_rows(rows, hangar_sel, _row_value, change_row)
	ui.build_stats(Parts.design_stats(design), Missions.LIST[hangar_mission].need)
	ui.set_go_text("Zum Startplatz 🚀")
	if rebuild or hangar_rocket == null:
		if hangar_rocket:
			hangar_rocket.queue_free()
		hangar_rocket = Parts.build_rocket(design); hangar_rocket.position.y = 1.5
		hangar.add_child(hangar_rocket)
	progress.design = design; _save_progress()

func open_hangar(mi: int) -> void:
	hangar_mission = mi; screen = "hangar"; hangar_warned = false
	title_paul.visible = false
	var need: String = Missions.LIST[mi].need
	var preset := "moon" if need == "moon" else ("orbit" if need == "orbit" else "hop")
	var d: Dictionary = progress.design if (progress.design is Dictionary and progress.design.has("stages") and Missions.LIST[mi].id != "hop") else Parts.PRESETS[preset]
	design = d.duplicate(true)
	if need != "" and Parts.design_stats(design).dv < Parts.NEED[need]:
		design = Parts.PRESETS[preset].duplicate(true)
	flight.clear()
	_world_visible(false)
	ui.show_only("hangar"); hangar_sel = 1
	refresh_hangar(true)
	say("hangar"); audio.set_music("werft")

func hangar_preset(key: String) -> void:
	design = Parts.PRESETS[key].duplicate(true); audio.sfx("snap"); refresh_hangar(true)

func hangar_launch() -> void:
	var st := Parts.design_stats(design)
	var need: String = Missions.LIST[hangar_mission].need
	if not hangar_warned and (st.twr < 1.0 or (need != "" and st.dv < Parts.NEED[need])):
		hangar_warned = true
		say("h_heavy" if st.twr < 1.0 else "h_short")
		ui.set_go_text("Trotzdem starten 🚀")
		return
	if not hangar_warned:
		say("h_ok")
	start_flight(hangar_mission, design.duplicate(true))

# =====================================================================
#  Eingabe
# =====================================================================
func touch_tap(n: String) -> void:
	touch_taps[n] = true

func cam_drag(rel: Vector2) -> void:
	if screen != "flight":
		return
	flight.cam_yaw -= rel.x * 0.006
	flight.cam_pitch = clampf(flight.cam_pitch + rel.y * 0.005, -1.3, 1.45)
	flight.dragging = true

func cam_zoom(k: float) -> void:
	if screen != "flight":
		return
	flight.cam_dist = clampf(flight.cam_dist * k, 8.0, 3.0e5)

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.keycode
	if k == KEY_T:
		audio.set_on(not audio.on); return
	match screen:
		"title":
			var n := Missions.LIST.size()
			if k == KEY_RIGHT or k == KEY_DOWN:
				title_sel = (title_sel + 1) % n; ui.build_cards(progress.done, title_sel); audio.sfx("click")
			elif k == KEY_LEFT or k == KEY_UP:
				title_sel = (title_sel + n - 1) % n; ui.build_cards(progress.done, title_sel); audio.sfx("click")
			elif k == KEY_ENTER or k == KEY_SPACE or k == KEY_KP_ENTER:
				begin_mission(title_sel)
			elif k >= KEY_1 and k <= KEY_7:
				begin_mission(k - KEY_1)
			elif k == KEY_I:
				show_facts()
			elif k == KEY_L:
				ui.toggle_lang()
		"hangar":
			var sel := _selectable()
			if k == KEY_DOWN:
				hangar_sel = mini(sel.size() - 1, hangar_sel + 1); audio.sfx("click"); refresh_hangar(false)
			elif k == KEY_UP:
				hangar_sel = maxi(0, hangar_sel - 1); audio.sfx("click"); refresh_hangar(false)
			elif k == KEY_RIGHT:
				change_row(hangar_sel, sel[hangar_sel], 1)
			elif k == KEY_LEFT:
				change_row(hangar_sel, sel[hangar_sel], -1)
			elif k == KEY_ENTER or k == KEY_KP_ENTER:
				hangar_launch()
			elif k == KEY_ESCAPE:
				show_title()
			elif k >= KEY_1 and k <= KEY_3:
				hangar_preset(["hop", "orbit", "moon"][k - KEY_1])
		"flight":
			if flight.paused:
				if k in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
					toggle_pause(false)
				return
			if k == KEY_ESCAPE:
				toggle_pause(true); return
			if k == KEY_M:
				ui.toggle_map()
			if k == KEY_I:
				ui.sci_on = not ui.sci_on; audio.sfx("click")
			if k == KEY_C:
				_next_cam()
			if k == KEY_SPACE:
				flight.pressed["fire"] = true
			if not flight.dock.is_empty():
				return
			if k == KEY_ENTER or k == KEY_KP_ENTER:
				if flight.vessel and not flight.vessel.on_pad:
					flight.do_stage()
			if k == KEY_UP or k == KEY_W:
				flight.sas = "pro"; audio.sfx("click")
			if k == KEY_DOWN or k == KEY_S:
				flight.sas = "retro"; audio.sfx("click")
			if k == KEY_B:
				_toggle_auto()
			if k == KEY_PERIOD:
				flight.warp_lock = minf(1000.0, flight.warp_lock * (10.0 if flight.warp_lock >= 10.0 else 2.0))
			if k == KEY_COMMA:
				flight.warp_lock = maxf(1.0, flight.warp_lock / (10.0 if flight.warp_lock > 10.0 else 2.0))
		"result":
			if k in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
				result_next()
			elif k == KEY_N or k == KEY_R:
				restart_mission()
			elif k == KEY_ESCAPE:
				show_title()
		"facts":
			if k in [KEY_ESCAPE, KEY_ENTER]:
				show_title()

func _next_cam() -> void:
	flight.set_cam_mode(flight.cam_mode + 1); flight.dragging = false
	audio.sfx("click"); ui.big_msg("📷 " + T.t(flight.CAM_MODES[flight.cam_mode].name), true)

func _toggle_auto() -> void:
	var M = flight.M
	if flight.vessel == null or M == null or not M.has_auto():
		return
	flight.auto = not flight.auto
	say("autop" if flight.auto else "manual")
	if flight.auto and flight.vessel.on_pad and flight.countdown < 0.0 and M.phase == "pad":
		flight.start_countdown(); M.phase = "count"

func _gather_input() -> void:
	var th: Dictionary = ui.touch.held
	var key := func(k: int) -> bool: return Input.is_key_pressed(k)
	flight.inp = {
		"fire": key.call(KEY_SPACE) or th.has("fire"),
		"left": key.call(KEY_LEFT) or key.call(KEY_A) or th.has("left"),
		"right": key.call(KEY_RIGHT) or key.call(KEY_D) or th.has("right"),
		"up": key.call(KEY_UP) or key.call(KEY_W) or th.has("up"),
		"down": key.call(KEY_DOWN) or key.call(KEY_S) or th.has("down"),
		"warp": key.call(KEY_F) or th.has("warp"),
	}
	for n in touch_taps:
		match n:
			"fire": flight.pressed["fire"] = true
			"stage":
				if flight.vessel and not flight.vessel.on_pad:
					flight.do_stage()
			"up":
				if flight.dock.is_empty(): flight.sas = "pro"
			"down":
				if flight.dock.is_empty(): flight.sas = "retro"
			"cam": _next_cam()
			"auto": _toggle_auto()
			"sci": ui.sci_on = not ui.sci_on
	touch_taps.clear()

# =====================================================================
#  Pro Bild
# =====================================================================
var _hud_t := 0.0
func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	var focus := cam.global_position
	if screen == "hangar":
		_hangar_frame(dt)
	elif screen == "flight" or screen == "result":
		if screen == "flight" and not flight.paused:
			_gather_input()
			flight.frame(dt)
		elif screen == "result":
			flight.inp = {"fire": false, "left": false, "right": false, "up": false, "down": false, "warp": false}
			flight.frame(dt)
		else:
			flight.update_camera(dt)
		var b = flight.cam_body()
		if b != null:
			focus = Vector3(b.x, b.y, 0)
		_hud_t -= dt
		if _hud_t <= 0.0:
			_hud_t = 0.1; ui.update_hud(flight)
	else:
		_title_camera(dt)
	flight.pressed = {}
	if screen != "hangar":
		world.update_world(dt, cam, flight.t, focus)
	if not audio.speaking() and ui.caption.visible and screen in ["title", "facts"]:
		pass

func _title_camera(dt: float) -> void:
	title_a += dt * 0.025; flight.t += dt * 5.0
	var a := 1.3 + sin(title_a) * 0.5
	var pos := Vector3(cos(a) * P.R * 2.05, sin(a) * P.R * 2.05, P.R * 0.55)
	cam.look_at_from_position(pos, Vector3(cos(a + 0.55) * P.R * 0.35, sin(a + 0.55) * P.R * 0.35, -P.R * 0.15), Vector3(0, 0, 1))
	cam.near = 0.1
	# Paul schwebt rechts unten vor der Kamera
	var t := Time.get_ticks_msec() / 1000.0
	var cb := cam.global_transform.basis
	title_paul.visible = true
	title_paul.global_transform = Transform3D(cb * Basis(Vector3(0, 1, 0), -0.5 + sin(t * 0.4) * 0.15) * Basis(Vector3(0, 0, 1), sin(t * 0.7) * 0.12), cam.global_position + cb * Vector3(2.3, -1.6 + sin(t * 0.9) * 0.08, -5.2))
	Toon.animate(title_paul, t, true)

func _hangar_frame(dt: float) -> void:
	if hangar_rocket == null:
		return
	if hangar_ready_lights:
		hangar_ready_lights = false
		for c in hangar.get_children():
			if c is DirectionalLight3D:
				var d: Vector3 = c.get_meta("dir")
				c.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.FORWARD), hangar.global_position)
	Toon.animate(hangar_paul, Time.get_ticks_msec() / 1000.0, true)
	hangar_spin += dt * 0.25
	hangar_rocket.rotation.y = hangar_spin
	(hangar.get_node("Plate") as Node3D).rotation.y = hangar_spin
	var h: float = hangar_rocket.get_meta("h")
	var dist := h * 1.35 + 14.0
	var a := 0.35
	# Rakete etwas nach rechts schieben, links ist der Baukasten
	var target := hangar.global_position + Vector3(-h * 0.12, h * 0.5, 0)
	cam.look_at_from_position(hangar.global_position + Vector3(sin(a) * dist - h * 0.12, h * 0.55 + 4.0, cos(a) * dist), target, Vector3.UP)
	cam.near = 0.2
