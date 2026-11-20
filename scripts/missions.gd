extends RefCounted
## Die Missionen. Eine Instanz pro Flug; die Logik hängt an der Missions-ID.

const P := preload("res://scripts/phys.gd")
const Parts := preload("res://scripts/parts.gd")
const T := preload("res://scripts/lang.gd")   # Übersetzung; die meisten Texte übersetzt erst ui.gd beim Anzeigen

const LIST := [
	{"id": "hop", "icon": "🚀", "title": "Erster Flug", "sub": "Bau eine Rakete und flieg ins Weltall – und mit dem Fallschirm zurück.", "need": "space", "build": true},
	{"id": "orbit", "icon": "🌍", "title": "Rund um die Erde", "sub": "Flieg so schnell zur Seite, dass du nicht mehr runterfällst!", "need": "orbit", "build": true},
	{"id": "home", "icon": "🔥", "title": "Sicher nach Hause", "sub": "Bremsen, glühen, Fallschirm – und Platsch ins Meer.", "need": "", "build": false},
	{"id": "iss", "icon": "🛰️", "title": "Besuch bei der ISS", "sub": "Hol die Raumstation ein und dock an.", "need": "", "build": false},
	{"id": "issd", "icon": "🌊", "title": "Die ISS kommt heim", "sub": "Bremse die alte ISS genau zum Punkt Nemo.", "need": "", "build": false},
	{"id": "moon", "icon": "🌙", "title": "Um den Mond herum", "sub": "Die große Reise: zum Mond und wieder zurück!", "need": "moon", "build": true},
	{"id": "free", "icon": "✨", "title": "Freies Fliegen", "sub": "Bau, was du willst, und flieg, wohin du willst.", "need": "", "build": true},
]
const FACTS := {
	"hop": ["Die Erde zieht alles zu sich hin. Das heißt Schwerkraft.", "Ab 100 km Höhe beginnt der Weltraum.", "Oben ist der Himmel schwarz, weil dort keine Luft das Sonnenlicht verteilt.", "Ein Fallschirm bremst, weil er ganz viel Luft fängt."],
	"orbit": ["Orbit heißt: Man fällt die ganze Zeit – aber so schnell zur Seite, dass man immer an der Erde vorbeifällt.", "Dafür braucht man 28.000 km/h – 100-mal so schnell wie ein Auto.", "Raketen fliegen erst hoch und kippen dann zur Seite.", "Leere Stufen wirft man ab, dann ist die Rakete leichter.", "Am Hochpunkt Gas geben hebt die andere Seite der Bahn an."],
	"home": ["Um runterzukommen, bremst man gegen die Flugrichtung.", "Beim Eintauchen in die Luft wird es über 1500 Grad heiß – die Luft glüht!", "Der Hitzeschild schützt die Astronauten.", "Dann bremsen Fallschirme, und ein Schiff holt die Kapsel aus dem Meer."],
	"iss": ["Die ISS ist so groß wie ein Fußballfeld und fliegt 400 km hoch.", "Seit dem Jahr 2000 wohnen dort immer Astronauten.", "Komischer Trick: Wer tiefer fliegt, ist schneller und holt auf.", "Beim Andocken fliegt man ganz langsam – nur ein paar Zentimeter pro Sekunde."],
	"issd": ["Die ISS wird um 2030 von einem Bremsschiff nach unten geschoben.", "Sie fällt in den Pazifik beim Punkt Nemo – dem Ort, der am weitesten von allen Menschen entfernt ist.", "Dort liegen schon viele alte Raumschiffe – ein Raumschiff-Friedhof.", "Die meisten Teile verglühen in der Luft wie Sternschnuppen."],
	"moon": ["Der echte Mond ist 384.000 km weit weg. Die Apollo-Astronauten brauchten 3 Tage dorthin.", "Mit dem richtigen Schwung zieht der Mond die Rakete herum und schickt sie zurück: die freie Rückkehr.", "Vom Mond aus sieht die Erde ganz klein und blau aus.", "Zurück kommt man sehr schnell an – darum glüht der Hitzeschild besonders stark."],
	"free": ["Du kannst alles ausprobieren: Orbit, ISS, Mond!", "Knopf Computer: Der Bordcomputer fliegt dich in den Orbit.", "Tipp auf die Karte für die große Ansicht."],
}
const NEMO_PHI := 300.0 * PI / 180.0
const NEMO_W := 13.0 * PI / 180.0
const NEMO_BURN := 186.0 * PI / 180.0
const MOON_LEAD := 108.0 * PI / 180.0

var f              # Flight
var main
var id := ""
var index := 0
var design := {}
var phase := ""
var asc := ""
var finished := false
var S := {}        # Zustand der Mission
var map_moon := false
var land_bad := false

func _init(flight, main_node, i: int, d: Dictionary) -> void:
	f = flight; main = main_node; index = i; id = LIST[i].id; design = d
	map_moon = id == "moon"
	land_bad = id == "issd"

func say(line: String) -> void:
	f.say(line)

func finish(ok: bool, icon: String, title: String, facts_key: String, delay := 3.5) -> void:
	if finished:
		return
	finished = true
	if ok:
		main.mark_done(id)
	main.get_tree().create_timer(delay).timeout.connect(func(): main.show_result(ok, icon, title, facts_key, index))

func has_auto() -> bool:
	return id in ["orbit", "moon", "free"]

func auto_throttle(v) -> float:
	if id == "moon" and asc == "orbit":
		if phase == "tli":
			return 1.0
		return 1.0 if S.get("mcc_burn", false) else 0.0
	return f.autopilot_ascent(v)

## Zeitraffer, wenn der Bordcomputer fliegt und gerade nur gewartet wird
func auto_warp() -> bool:
	if not f.auto or f.vessel == null:
		return false
	var v = f.vessel
	if asc == "coast":
		return true
	if id == "moon" and asc == "orbit":
		if phase in ["wait", "coast"]:
			return true
		if phase == "return":
			return sqrt(v.x * v.x + v.y * v.y) - P.R > 7000.0
	return false

# =====================================================================
#  Gemeinsam: Start vom Startplatz, Aufstieg mit Hilfe
# =====================================================================
func pad_flight(d: Dictionary) -> void:
	var v = f.new_vessel(d)
	f.place_on_pad(v)
	f.lock_engine = true
	f.cam_base = v.h * 1.25 + 16.0; f.set_cam_mode(0); f.snap_cam()
	phase = "pad"; say("pad")
	f.keys_hint = [["Motor = Countdown ⏱", true]]; f.objective = "Drück den Motor-Knopf zum Starten"
	main.audio.set_music("launch")

func pad_update() -> bool:
	var v = f.vessel
	if phase == "pad":
		if f.pressed.get("fire", false):
			f.start_countdown(); phase = "count"; f.keys_hint = [["Countdown …", false]]
		return true
	if phase == "count":
		if f.countdown < 0.0:
			phase = "go"; S.go_at = f.t
		return true
	if phase == "go" and v.on_pad:
		f.keys_hint = [["Motor halten 🔥", true]]
		if not f.inp.fire and f.t - S.go_at > 1.5:
			f.say_once("hold")
		var st := Parts.design_stats(v.design)
		if st.twr < 1.0 and f.t - S.go_at > 4.0:
			f.say_once("h_heavy", "heavy_pad")
		return true
	return false

func ascent_help(dt: float) -> void:
	var v = f.vessel
	if v == null or v.landed:
		return
	var g: Dictionary = f.ascent_guide(v)
	f.guide_hd = g.hd; f.show_guide = asc != "orbit"
	var alt: float = sqrt(v.x * v.x + v.y * v.y) - P.R
	var thr: bool = v.throttle > 0.0
	if asc == "orbit":
		return
	if asc == "":
		asc = "ascent"
	if asc == "ascent":
		f.objective = "Flieg zum goldenen Stern, bis der Hochpunkt 400 km erreicht"
		var off: float = P.ang_diff(g.hd, v.hd)
		if alt > 250.0 and absf(off) > 0.3 and not f.auto:
			if not S.has("tilt_said") or f.t - S.tilt_said > 14.0:
				S.tilt_said = f.t; say("tilt")
			f.keys_hint = [["▶ kippen" if off > 0.0 else "◀ kippen", true], ["Motor 🔥", not thr]]
		else:
			f.keys_hint = [["Motor 🔥", not thr], ["Computer fliegt", false]]
			if alt > 600.0 and S.has("tilt_said") and not S.has("good_said"):
				S.good_said = true; say("good")
		if g.el.ap >= P.ORBIT_ALT - 300.0:
			asc = "coast"; f.cut = true; say("apo_ok"); main.audio.sfx("ding"); f.sas = "guide"
	elif asc == "coast":
		f.sas = "guide"
		var tta := P.time_to_apo(v.x, v.y, v.vx, v.vy)
		f.objective = "Warte bis ganz oben (Zeitraffer ⏩)"
		f.keys_hint = [["⏩ halten", not f.inp.warp], ["Karte", false]]
		if not S.has("coast_said") and not f.speaking():
			S.coast_said = true; say("coast")
		if tta < 14.0 or (g.el.ap < P.ORBIT_ALT - 800.0 and alt > P.ATM):
			asc = "circ"; say("circ"); main.audio.sfx("ding"); f.sas = "guide"
	elif asc == "circ":
		f.sas = "guide"
		f.objective = "Gas geben, bis der Tiefpunkt aus der Luft raus ist"
		f.keys_hint = [["Motor 🔥", not thr]]
		if g.el.pe > P.ATM + 1500.0 or (g.el.pe > P.ATM + 300.0 and g.el.ap > P.ORBIT_ALT + 3000.0):
			asc = "orbit"; f.cut = true; f.sas = "pro"
			if id != "moon": f.auto = false   # Mondmission: Computer fliegt weiter bis nach Hause
			main.audio.sfx("win"); main.audio.set_music("space")
			on("orbit", null)

func ascent_warp_cap() -> float:
	var v = f.vessel
	if v == null or asc != "coast":
		return 1e9
	return 1.0 if P.time_to_apo(v.x, v.y, v.vx, v.vy) < 30.0 else 1e9

func landed_lines(L: Dictionary) -> void:
	if L.sea:
		say("splash")
	elif L.speed > 14.0:
		say("hard")
	else:
		say("land")

func std_on(e: String, d) -> void:
	match e:
		"boosters": say("boosters")
		"staging": say("staging")
		"capsule":
			var v = f.vessel
			if sqrt(v.x * v.x + v.y * v.y) - P.R < P.ATM + 2000.0 and sqrt(v.vx * v.vx + v.vy * v.vy) > 300.0:
				say("drop_engine")
			else:
				say("capsule")
		"chute": say("chute")
		"crash":
			say("moon_crash" if d == "moon" else "crash")
			main.audio.sfx("sad")
			if id != "free":
				finish(false, "💥", "Bumm! Nochmal probieren", "", 3.0)
		"sunrise":
			if asc == "orbit": f.say_once("sunrise")
		"night":
			if asc == "orbit": f.say_once("night")

# =====================================================================
#  Einrichten
# =====================================================================
func setup() -> void:
	match id:
		"hop":
			pad_flight(design); f.show_guide = false
		"orbit":
			pad_flight(design)
		"home":
			var v = f.new_vessel({"color": 3, "stages": [{"tanks": 1, "engine": "vac", "boosters": 0, "fins": false}]})
			v.st[0].fuel = v.st[0].fuel0 * 0.45
			f.place_in_orbit(v, deg_to_rad(205.0)); f.max_throttle = 0.3; f.sas = "pro"
			f.cam_base = v.h * 1.6 + 22.0; f.set_cam_mode(1); f.snap_cam()
			phase = "intro"; asc = "orbit"; say("home1"); main.audio.set_music("space")
		"iss":
			f.iss = f.make_iss_body(deg_to_rad(110.0))
			var v = f.new_vessel({"color": 4, "stages": [{"tanks": 1, "engine": "vac", "boosters": 0, "fins": false}]})
			v.st[0].fuel = v.st[0].fuel0 * 0.5
			f.place_in_orbit(v, deg_to_rad(102.0)); f.max_throttle = 0.12; f.sas = "pro"
			f.cam_base = v.h * 1.6 + 22.0; f.set_cam_mode(1); f.snap_cam()
			phase = "intro"; asc = "orbit"; say("iss1"); main.audio.set_music("space")
		"issd":
			var b: Dictionary = f.make_iss_body(deg_to_rad(120.0))
			b.dynamic = true
			f.iss = b
			f.cam_target = b; f.cam_base = 170.0; f.set_cam_mode(1); f.snap_cam()
			S.queue = ["issd1", "issd2", "issd3", "issd4"]; phase = "talk"
			main.audio.set_music("space")
			say(S.queue.pop_front())
		"moon":
			P.moon_theta0 = deg_to_rad(300.0)
			pad_flight(design)
		"free":
			f.iss = f.make_iss_body(deg_to_rad(40.0))
			pad_flight(design)
			main.get_tree().create_timer(0.3).timeout.connect(func(): say("free"))

# =====================================================================
#  Pro Bild
# =====================================================================
func update(dt: float) -> void:
	match id:
		"hop": _hop(dt)
		"orbit": _orbit(dt)
		"home": _home(dt)
		"iss": _iss(dt)
		"issd": _issd(dt)
		"moon": _moon(dt)
		"free": _free(dt)

func _hop(_dt: float) -> void:
	if pad_update():
		return
	var v = f.vessel
	if v.landed:
		return
	f.guide_hd = atan2(v.y, v.x)
	var r: float = sqrt(v.x * v.x + v.y * v.y)
	var alt := r - P.R
	var vr: float = (v.x * v.vx + v.y * v.vy) / r
	f.objective = "Flieg in den Weltraum – über 100 km hoch!" if f.max_alt < P.SPACE_ALT else "Jetzt sicher landen!"
	var has_fuel: bool = not v.capsule_only() and not v.all_empty()
	if has_fuel:
		f.keys_hint = [] if v.throttle > 0.0 else [["Motor 🔥", alt < P.SPACE_ALT]]
	else:
		f.keys_hint = [["⏩ halten", not f.inp.warp]] if alt > P.ATM else []
	if not has_fuel and alt > P.ATM + 3000.0 and f.said_once.has("evt_space") and not f.speaking():
		f.say_once("warp")
	if vr < 0.0 and not S.has("fall_said") and alt > 300.0:
		S.fall_said = true
		if not f.speaking():
			say("falling")

func _orbit(dt: float) -> void:
	if pad_update():
		return
	ascent_help(dt)
	if asc == "orbit":
		f.objective = "Du bist im Orbit! 🎉"; f.keys_hint = [["Karte", false], ["⏩ Zeitraffer", false]]

func _home(_dt: float) -> void:
	var v = f.vessel
	if v == null:
		return
	var pro: float = atan2(v.vy, v.vx)
	if phase == "intro":
		f.objective = "Dreh die Rakete nach hinten"; f.keys_hint = [["Zurück ⤺", true]]
		if (not f.speaking() or f.sas == "retro") and not S.has("r1"):
			S.r1 = true; say("retro")
		if f.sas == "retro" and absf(P.ang_diff(pro + PI, v.hd)) < 0.12:
			phase = "burn"; say("burn_retro")
	elif phase == "burn":
		f.objective = "Bremsen, bis die Linie in die Luft taucht"; f.keys_hint = [["Motor = bremsen 🔥", v.throttle == 0.0], ["Karte", false]]
		var el := P.elements(v.x, v.y, v.vx, v.vy)
		if f.pred.has("impact") and el.pe < 1800.0:
			phase = "fall"; f.cut = true; say("home_ok"); main.audio.sfx("ding")
	elif phase == "fall":
		f.objective = "Nach Hause fallen …"; f.keys_hint = [["⏩ halten", not f.inp.warp]]
		if v.heat > 0.35:
			f.say_once("hot")

func iss_dist() -> float:
	var v = f.vessel
	return sqrt(pow(v.x - f.iss.x, 2.0) + pow(v.y - f.iss.y, 2.0))

func _iss(_dt: float) -> void:
	var v = f.vessel
	if v == null:
		return
	var el := P.elements(v.x, v.y, v.vx, v.vy)
	if phase == "intro":
		f.objective = "Hol die ISS ein!"; f.keys_hint = []
		if not f.speaking():
			phase = "turn"; say("iss2")
	elif phase == "turn":
		f.objective = "Ein kleines bisschen bremsen"
		f.keys_hint = [["Zurück ⤺", f.sas != "retro"], ["Motor = bremsen 🔥", f.sas == "retro" and v.throttle == 0.0]]
		if el.pe < P.ORBIT_ALT - 1500.0:
			phase = "chase"; f.cut = true; main.audio.sfx("ding"); say("iss3"); f.sas = "pro"
	elif phase == "chase":
		f.objective = "Warten und aufholen (⏩ Zeitraffer)"; f.keys_hint = [["⏩ halten", not f.inp.warp]]
		if iss_dist() < 3800.0:
			phase = "dock"; f.warp = 1.0; say("iss4"); S.dock_at = f.t + 3.5
	elif phase == "dock" and f.dock.is_empty() and f.t > S.dock_at:
		f.start_dock()
		f.objective = "Andocken am gelben Ring"; say("dock1")
		f.keys_hint = [["◀ ▶ ▲ ▼ zielen", true], ["Motor = langsam vor", false]]

func _make_tug() -> Node3D:
	var W := preload("res://scripts/world.gd")
	var g := Node3D.new()
	var white := W.mat(Color(0.95, 0.96, 0.97), 0.45, 0.1)
	var body := W.cyl(2, 2, 7, white); body.rotation.x = PI / 2.0; body.position.z = 4.5; g.add_child(body)
	var ring := W.cyl(2.05, 2.05, 0.6, W.mat(Color(0.18, 0.44, 0.88))); ring.rotation.x = PI / 2.0; ring.position.z = 6.0; g.add_child(ring)
	for sx in [-1, 1]:
		var pnl := W.box(Vector3(5, 0.1, 2.6), W.mat(Color(0.11, 0.2, 0.45), 0.3, 0.6)); pnl.position = Vector3(sx * 4.5, 0, 3); g.add_child(pnl)
	var flames := []
	for xy in [[-0.9, -0.9], [0.9, -0.9], [-0.9, 0.9], [0.9, 0.9]]:
		var nz := W.cyl(0.18, 0.55, 0.6, W.mat(Color(0.17, 0.2, 0.25))); nz.rotation.x = -PI / 2.0; nz.position = Vector3(xy[0], xy[1], 8.4); g.add_child(nz)
		var fl := Parts.make_flame(0.55); fl.rotation.x = -PI / 2.0; fl.position = Vector3(xy[0], xy[1], 8.7); g.add_child(fl); flames.append(fl)
	g.set_meta("flames", flames)
	return g

func in_zone() -> bool:
	return f.pred.has("impact") and absf(P.ang_diff(f.pred.impact.phi, NEMO_PHI)) < NEMO_W

func _issd(dt: float) -> void:
	var b = f.iss
	if b == null:
		return
	var r: float = sqrt(b.x * b.x + b.y * b.y)
	var alt := r - P.R
	var phi: float = atan2(b.y, b.x)
	b.decay = 0.0; b.thrust = 0.0
	match phase:
		"talk":
			f.keys_hint = []; f.objective = "Die alte ISS"
			if not f.speaking():
				if S.queue.size() > 0:
					say(S.queue.pop_front())
				else:
					phase = "decay"
		"decay":
			f.objective = "⏩ halten: Die Station sinkt langsam"; f.keys_hint = [["⏩ halten", not f.inp.warp]]
			if f.warp > 1.5:
				b.decay = 5.5e-6
			if alt < 12500.0:
				var v0 := sqrt(P.GM / r)
				b.vx = -v0 * sin(phi); b.vy = v0 * cos(phi)
				phase = "tugtalk"; say("issd5"); f.warp = 1.0
		"tugtalk":
			if not S.has("tug"):
				S.tug = _make_tug(); b.node.add_child(S.tug); S.tug_t = 0.0; b.tug = {"fuel": 1.0}
			S.tug_t += dt / 6.0
			var k := 1.0 - pow(1.0 - minf(1.0, S.tug_t), 3.0)
			S.tug.position = b.node.get_meta("port") + Vector3(0, 0, (1.0 - k) * 160.0)
			f.objective = "Das Bremsschiff kommt"; f.keys_hint = []
			if S.tug_t >= 1.0 and not S.has("docked"):
				S.docked = true; main.audio.sfx("dock"); say("issd6")
			if S.has("docked") and not f.speaking():
				phase = "burn"; say("issd7")
		"burn":
			var fire: bool = f.inp.fire and b.tug.fuel > 0.0
			var back: bool = f.inp.up and b.tug.fuel > 0.0
			b.thrust = -1.5 if fire else (0.6 if back else 0.0)
			if b.thrust != 0.0:
				b.tug.fuel = maxf(0.0, b.tug.fuel - dt / 50.0)
			for fl in S.tug.get_meta("flames"):
				fl.visible = fire
				if fire:
					fl.scale = Vector3(0.55, randf_range(5.0, 6.0), 0.55)
			var near := absf(P.ang_diff(phi, NEMO_BURN))
			var imp = f.pred.get("impact", null)
			var zone := in_zone()
			f.objective = "Bring das rote Kreuz ins gelbe Ziel"
			f.keys_hint = [["Motor = bremsen 🔥", not fire and (near < 0.25 or imp != null)], ["Vor = bisschen Gas", imp != null and P.ang_diff(imp.phi, NEMO_PHI) < -NEMO_W]]
			if zone and not fire:
				S.good_t = S.get("good_t", 0.0) + dt
				if S.good_t > 0.8:
					phase = "fall"; say("issd_good"); main.audio.sfx("ding")
					for fl in S.tug.get_meta("flames"):
						fl.visible = false
			else:
				S.good_t = 0.0
			if phase == "burn" and not fire:
				var line := ""
				if imp != null and not zone:
					line = "issd_landx" if imp.land else ("issd_more" if P.ang_diff(imp.phi, NEMO_PHI) > 0.0 else "issd_less")
				elif imp == null and near > 0.3:
					line = "issd_wait"
				if line != "" and line != S.get("last_line", "") and f.t - S.get("line_at", -100.0) > 6.0 and not f.speaking():
					S.last_line = line; S.line_at = f.t; say(line)
			if b.tug.fuel <= 0.0 and not zone and phase == "burn":
				phase = "fall"
		"fall":
			f.objective = "Die Station fällt …"; f.keys_hint = [["⏩ halten", not f.inp.warp]]
			if alt < P.ATM + 200.0:
				phase = "air"; say("issd_air"); f.cam_base = 150.0; f.set_cam_mode(1)
		"air":
			f.keys_hint = []
			var sp: float = sqrt(b.vx * b.vx + b.vy * b.vy)
			f.iss_heat = clampf((sqrt(P.rho(alt)) * sp * sp * sp - 0.8e7) / 1.5e7, 0.0, 1.0)
			_iss_glow(f.iss_heat)
			if alt < 3500.0 and not S.has("panels"):
				S.panels = true; _break_panels(); main.audio.sfx("crack"); say("issd_panels")
			if alt < 2900.0 and not S.has("broken"):
				S.broken = true; _break_up(); main.audio.sfx("crack"); main.audio.sfx("boom")
				main.get_tree().create_timer(1.5).timeout.connect(func(): say("issd_break"))
				phase = "pieces"
		"pieces":
			var alive := []
			for d in f.debris:
				if d.kind == "iss" and d.survive and d.alive:
					alive.append(d)
			if alive.size() > 0:
				alive.sort_custom(func(a, c): return a.mass > c.mass)
				f.cam_target = alive[0]
			elif not S.has("judged"):
				S.judged = true; _judge()

func _iss_glow(h: float) -> void:
	var b = f.iss
	if not S.has("plasma"):
		S.plasma = Parts.make_plasma(); f.add_child(S.plasma)
	var pl: MeshInstance3D = S.plasma
	pl.visible = h > 0.02 and not S.has("broken")
	if not pl.visible:
		return
	var va: float = atan2(b.vy, b.vx)
	var len := 60.0 + h * 160.0
	var dir := Vector3(cos(va), sin(va), 0)
	pl.global_transform = Transform3D(f.basis_heading(va) * Basis.from_scale(Vector3(18.0 + h * 22.0, len, 18.0 + h * 22.0)), Vector3(b.x, b.y, 0) + dir * (40.0 - len * 0.5))
	pl.material_override.set_shader_parameter("power", h)

func _break_panels() -> void:
	var b = f.iss
	for w in b.node.get_meta("wings"):
		var wp: Vector3 = w.global_position
		var d: Dictionary = f.add_debris(w, wp.x, wp.y, b.vx * (1.0 - randf() * 0.01) + randf_range(-4, 4), b.vy * (1.0 - randf() * 0.01) + randf_range(-4, 4), atan2(b.vy, b.vx), randf_range(-1.5, 1.5), 400.0, 900.0, "iss")
		d.survive = false; d.burn = 1.5 + randf()

func _break_up() -> void:
	var b = f.iss
	var body: Node3D = b.node.get_node("Body")
	var k := 0
	for p in body.get_children():
		var wp: Vector3 = p.global_position
		var big: bool = p.has_meta("module") and k < 3
		var d: Dictionary = f.add_debris(p, wp.x, wp.y, b.vx + randf_range(-7, 7), b.vy + randf_range(-7, 7), atan2(b.vy, b.vx), randf_range(-1, 1),
			(60.0 + k * 15.0) if big else randf_range(120.0, 320.0), 30000.0 if big else randf_range(3000.0, 7000.0), "iss")
		if big:
			k += 1; d.survive = true
		else:
			d.survive = false; d.burn = randf_range(0.6, 2.6)
	if S.has("tug"):
		var wp: Vector3 = S.tug.global_position
		var d: Dictionary = f.add_debris(S.tug, wp.x, wp.y, b.vx, b.vy, atan2(b.vy, b.vx), 0.5, 90.0, 8000.0, "iss")
		d.survive = false; d.burn = 2.5
	b.alive = false; b.node.visible = false
	if S.has("plasma"):
		S.plasma.visible = false
	for d in f.debris:
		if d.survive and d.alive:
			f.cam_target = d; break
	f.cam_base = 120.0; f.set_cam_mode(1)

func _judge() -> void:
	var hits := []
	for d in f.debris:
		if d.kind == "iss" and d.survive and d.has("landed_at"):
			hits.append(d)
	var inz := hits.size() > 0
	var land := false
	for d in hits:
		var a: float = atan2(d.landed_at.y, d.landed_at.x)
		if absf(P.ang_diff(a, NEMO_PHI)) >= NEMO_W + deg_to_rad(5.0):
			inz = false
		if not d.sea:
			land = true
	if hits.size() > 0:
		var last: Dictionary = hits[0]
		f.cam_target = {"x": last.landed_at.x, "y": last.landed_at.y, "vx": 0.0, "vy": 0.0}
		f.cam_base = 300.0; f.set_cam_mode(2)
	if not land and inz:
		main.get_tree().create_timer(1.2).timeout.connect(func(): say("issd_splash"))
		main.audio.sfx("win")
		finish(true, "🌊", "Die ISS ist beim Punkt Nemo!", "issd", 9.0)
	elif not land:
		say("issd_sea"); finish(false, "🌊", "Im Meer – aber nicht ganz beim Punkt Nemo", "", 7.0)
	else:
		say("issd_fail"); main.audio.sfx("sad"); finish(false, "🏝️", "Teile sind auf Land gefallen", "", 7.0)

func moon_window() -> float:
	return P.moon_angle(f.t) - MOON_LEAD

## Bordcomputer: Kurskorrektur wie bei Apollo. Rechnet erst mit der Vorausschau durch,
## welcher kleine Schub (vorwärts oder rückwärts) die Bahn um den Mond zurück zur Erde bringt,
## und gibt dann ganz sanft in diese Richtung Gas, bis die Vorausschau passt (ok).
func _auto_mcc(dt: float, ok: bool) -> void:
	var v = f.vessel
	if ok or v == null or v.capsule_only() or v.all_empty():
		if S.get("mcc_burn", false) or S.has("mcc_plan"):
			S.mcc_burn = false; f.max_throttle = 1.0; S.erase("mcc_plan")
		return
	if not S.has("mcc_plan"):
		if f.t < S.get("mcc_retry", -1.0):
			return
		S.mcc_plan = _mcc_plan(v); S.mcc_t = 0.0
		if is_nan(S.mcc_plan):   # nichts gefunden: etwas später nochmal rechnen
			S.erase("mcc_plan"); S.mcc_burn = false; f.max_throttle = 1.0
			S.mcc_retry = f.t + 60.0
			return
	var dv: float = S.mcc_plan
	S.mcc_burn = true
	f.sas = "pro" if dv > 0.0 else "retro"
	f.max_throttle = 0.03
	S.mcc_t += dt
	if S.mcc_t > 6.0 + absf(dv) * 3.0:   # zu lange ohne Treffer: neu rechnen
		S.erase("mcc_plan")

func _mcc_plan(v) -> float:
	var sp: float = sqrt(v.vx * v.vx + v.vy * v.vy)
	var ux: float = v.vx / sp
	var uy: float = v.vy / sp
	var best := NAN
	var best_score := INF
	var opts := {"long": true, "stop_atm": true, "max_t": 14000.0}
	for i in range(-120, 121):
		var dvi := i * 0.25
		var p: Dictionary = P.predict(v.x, v.y, v.vx + ux * dvi, v.vy + uy * dvi, f.t, v.cd_a(), v.mass(), opts)
		if p.get("back", false) and not p.has("moon_hit"):
			var m_alt: float = p.moon_min - P.RMOON
			if m_alt > 5000.0 and m_alt < 28000.0:
				var score := absf(dvi) + absf(m_alt - 14000.0) * 0.0004
				if score < best_score:
					best_score = score; best = dvi
	print("MCC plan dv=", best)
	return best

func _moon(dt: float) -> void:
	if pad_update():
		return
	if asc != "orbit":
		ascent_help(dt); return
	var v = f.vessel
	var phi: float = atan2(v.y, v.x)
	var ma := P.moon_angle(f.t)
	var dm: float = sqrt(pow(v.x - P.RM * cos(ma), 2.0) + pow(v.y - P.RM * sin(ma), 2.0))
	var p: Dictionary = f.pred
	if phase == "go":
		phase = "wait"
		main.get_tree().create_timer(4.0).timeout.connect(func(): say("moon2"))
	match phase:
		"wait":
			var d: float = P.ang_diff(phi, moon_window())
			f.objective = "Warten, bis du beim grünen Pfeil bist"; f.keys_hint = [["⏩ halten", not f.inp.warp], ["Karte", false]]
			if d > -0.07 and d < 0.12:
				phase = "tli"; say("moon3"); f.sas = "pro"; main.audio.sfx("ding")
		"tli":
			f.objective = "Gas geben – der Bordcomputer sagt, wann es reicht"; f.keys_hint = [["Motor 🔥", v.throttle == 0.0]]
			var m_alt: float = p.get("moon_min", INF) - P.RMOON
			# Bordcomputer: kurz vor dem Ziel Gas wegnehmen, damit er das schmale Rückkehr-Fenster trifft
			if f.auto:
				f.max_throttle = 0.15 if (m_alt < 80000.0 or p.has("moon_hit")) else 1.0
			if p.has("moon_min") and not p.has("moon_hit") and v.throttle > 0.0 and ((m_alt < 26000.0 and m_alt > 7000.0 and p.get("back", false)) or (m_alt < 12000.0 and m_alt > 7000.0)):
				phase = "coast"; f.cut = true; say("moon4"); main.audio.sfx("win"); S.coast_at = f.t; f.max_throttle = 1.0
			if P.ang_diff(phi, moon_window()) > 0.5 and v.throttle == 0.0 and not p.get("left_earth", false):
				phase = "wait"
			if v.capsule_only() or v.all_empty():
				phase = "coast"; S.coast_at = f.t
		"coast":
			f.objective = "Beim Mond! 🌙" if dm < 60000.0 else "Auf dem Weg zum Mond (⏩ Zeitraffer)"
			f.keys_hint = [["⏩ halten", not f.inp.warp]]
			if f.t - S.get("coast_at", 0.0) > 8.0 and not S.has("c5"):
				S.c5 = true; say("moon5")
			if dm < 45000.0 and not S.has("near"):
				S.near = true; say("moon6"); f.cam_base = 14.0; f.set_cam_mode(2)
			if S.has("near") and dm < 70000.0:
				S.dm_min = minf(S.get("dm_min", 1e12), dm)
				f.backdrop = Vector2(P.RM * cos(ma), P.RM * sin(ma)) if dm <= S.dm_min + 50.0 else Vector2.ZERO
			else:
				f.backdrop = Vector2.INF
			if S.has("near") and dm > 70000.0:
				if p.get("back", false):
					phase = "return"; say("moon7")
				elif not p.is_empty():
					phase = "fix"; say("moon8"); f.sas = "retro"
			# Bordcomputer: unterwegs Kurs korrigieren, bis die Bahn ums Mond herum zurück zur Erde führt
			if f.auto and not S.has("near") and phase == "coast":
				var far: bool = dm > 120000.0 and sqrt(v.x * v.x + v.y * v.y) - P.R > 60000.0
				var ma2: float = p.get("moon_min", INF) - P.RMOON
				var good: bool = p.get("back", false) and not p.has("moon_hit") and ma2 > 5000.0 and ma2 < 28000.0
				if far and not p.is_empty():
					_auto_mcc(dt, good)
				elif S.get("mcc_burn", false):
					_auto_mcc(dt, true)
		"fix":
			if f.auto and not p.is_empty():
				_auto_mcc(dt, p.get("back", false) or p.has("impact"))
			f.objective = "Nachsteuern, bis die Linie die Erde trifft"; f.keys_hint = [["Motor 🔥", v.throttle == 0.0]]
			if p.get("back", false) or p.has("impact"):
				phase = "return"; f.cut = true; say("moon7"); S.mcc_burn = false; f.max_throttle = 1.0
			if v.capsule_only():
				phase = "return"
		"return":
			if f.auto:
				var el := P.elements(v.x, v.y, v.vx, v.vy)
				var hi: bool = sqrt(v.x * v.x + v.y * v.y) - P.R > 30000.0 and dm > 60000.0
				if hi and not v.capsule_only() and not v.all_empty() and el.pe > P.ATM * 0.35:
					S.mcc_burn = true; f.sas = "retro"; f.max_throttle = 0.1
				elif S.get("mcc_burn", false):
					S.mcc_burn = false; f.max_throttle = 1.0
			f.objective = "Heimflug zur Erde (⏩ Zeitraffer)"; f.keys_hint = [["⏩ halten", not f.inp.warp]]; f.backdrop = Vector2.INF
			if v.heat > 0.35:
				f.say_once("hot")

func _free(_dt: float) -> void:
	if pad_update():
		return
	var v = f.vessel
	if not v.landed:
		var g: Dictionary = f.ascent_guide(v)
		f.guide_hd = g.hd; f.show_guide = asc != "orbit"
		if asc == "" and g.phase == "orbit":
			asc = "orbit"; on("orbit", null)
	f.objective = "Freies Fliegen"; f.keys_hint = [["Computer", false], ["Karte", false]]
	map_moon = sqrt(v.x * v.x + v.y * v.y) > 120000.0 or f.pred.get("max_r", 0.0) > 120000.0

# =====================================================================
#  Ereignisse
# =====================================================================
func on(e: String, d) -> void:
	match id:
		"hop":
			if e == "space":
				say("space"); main.audio.sfx("ding")
			elif e == "landed":
				landed_lines(d)
				var ok: bool = f.max_alt >= P.SPACE_ALT
				main.get_tree().create_timer(3.5).timeout.connect(func(): say("hop_done" if ok else "retry"))
				finish(ok, "🚀" if ok else "🪂", "Du warst im Weltraum!" if ok else "Fast! Noch höher fliegen", "hop", 8.0)
			else:
				std_on(e, d)
		"orbit":
			if e == "orbit":
				say("orbit")
				main.get_tree().create_timer(6.5).timeout.connect(func(): say("map"))
				finish(true, "🌍", "Du bist im Orbit!", "orbit", 13.0)
			elif e == "landed":
				landed_lines(d); finish(false, "🪂", "Zurück auf der Erde – noch mehr Tempo zur Seite!", "", 5.0)
			else:
				std_on(e, d)
		"home":
			if e == "landed":
				landed_lines(d); finish(true, "🔥", "Sicher gelandet!", "home", 6.0)
			else:
				std_on(e, d)
		"iss":
			if e == "docked":
				say("docked"); main.audio.sfx("win"); f.keys_hint = []
				finish(true, "🛰️", "Angedockt an der ISS!", "iss", 6.0)
			else:
				std_on(e, d)
		"issd":
			if e == "debris" and d.kind == "iss" and d.survive:
				f.shake = 1.0
		"moon":
			if e == "orbit":
				say("orbit"); phase = "go"
			elif e == "landed":
				landed_lines(d)
				if S.has("near"):
					finish(true, "🌙", "Einmal Mond und zurück!", "moon", 6.0)
				else:
					finish(false, "🪂", "Wieder auf der Erde – ab zum Mond beim nächsten Mal!", "", 5.0)
			else:
				std_on(e, d)
		"free":
			if e == "orbit":
				say("orbit"); main.audio.set_music("space"); asc = "orbit"
			elif e == "space":
				say("space")
			elif e == "landed":
				landed_lines(d)
			else:
				std_on(e, d)

func warp_cap() -> float:
	match id:
		"orbit":
			return ascent_warp_cap()
		"home":
			return 1.0 if phase in ["burn", "intro"] else 1e9
		"iss":
			if phase == "chase":
				return 10.0 if iss_dist() < 5000.0 else 100.0
			return 1.0 if phase == "dock" else 1e9
		"issd":
			match phase:
				"decay": return 100.0
				"tugtalk", "talk": return 1.0
				"burn":
					var phi: float = atan2(f.iss.y, f.iss.x)
					return 1.0 if (absf(P.ang_diff(phi, NEMO_BURN)) < 0.35 or f.inp.fire) else 20.0
				"fall":
					return 2.0 if sqrt(f.iss.x * f.iss.x + f.iss.y * f.iss.y) - P.R < P.ATM + 2500.0 else 50.0
			return 2.0
		"moon":
			if asc != "orbit":
				return ascent_warp_cap()
			var v = f.vessel
			if phase == "wait":
				return 1.0 if absf(P.ang_diff(atan2(v.y, v.x), moon_window())) < 0.35 else 100.0
			if phase in ["tli", "fix"]:
				return 1.0
	return 1e9

func pred_opts() -> Dictionary:
	if id == "issd":
		return {"max_t": 20000.0}
	if id == "moon" and phase in ["tli", "coast", "fix", "return"]:
		return {"long": true, "stop_atm": true, "max_t": 14000.0}
	if id == "free" and map_moon:
		return {"long": true, "max_t": 14000.0}
	return {}

func hud_extra() -> String:
	if id == "iss" and f.dock.is_empty() and f.vessel != null:
		return T.t("Abstand ISS  %d km") % int(iss_dist() / 1000.0 * P.ALT_K)
	return ""

func x_color() -> Color:
	if id == "issd":
		return Color(0.24, 0.86, 0.52) if in_zone() else Color(1.0, 0.23, 0.23)
	return Color(1.0, 0.23, 0.23)

## Zusätzliche Markierungen auf der Karte
func map_draw(c: Control, X: Callable, s: float) -> void:
	var font := c.get_theme_default_font()
	if id == "issd":
		var o: Vector2 = X.call(0.0, 0.0)
		c.draw_arc(o, P.R * s + 5.0, -(NEMO_PHI + NEMO_W), -(NEMO_PHI - NEMO_W), 24, Color(1, 0.82, 0.25), 9.0)
		var lp: Vector2 = X.call(cos(NEMO_PHI) * P.R * 1.22, sin(NEMO_PHI) * P.R * 1.22)
		c.draw_string(font, lp - Vector2(60, 0), T.t("🎯 Punkt Nemo"),HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(1, 0.82, 0.25))
		if phase == "burn":
			_marker(c, o, (P.R + 12500.0) * s + 26.0, NEMO_BURN, "hier bremsen", font)
	if id == "moon" and phase in ["wait", "tli"]:
		var o: Vector2 = X.call(0.0, 0.0)
		_marker(c, o, (P.R + P.ORBIT_ALT) * s + 22.0, moon_window(), "Start zum Mond", font)

func _marker(c: Control, o: Vector2, rr: float, a: float, text: String, font: Font) -> void:
	var p := o + Vector2(cos(a), -sin(a)) * rr
	var d := Vector2(cos(a), -sin(a))
	var side := Vector2(-d.y, d.x)
	c.draw_colored_polygon(PackedVector2Array([p - d * 6.0 + side * 12.0, p - d * 6.0 - side * 12.0, p - d * 22.0]), Color(0.24, 0.86, 0.52))
	c.draw_string(font, p + d * 22.0 - Vector2(70, -6), T.t(text), HORIZONTAL_ALIGNMENT_CENTER, 140, 18, Color(0.24, 0.86, 0.52))
