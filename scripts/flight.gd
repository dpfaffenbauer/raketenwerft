extends Node3D
## Der Flug: Physik, Stufen, Fallschirm, Landung, Zeitraffer, Kamera, Effekte, ISS, Trümmer, Andocken.

const P := preload("res://scripts/phys.gd")
const Parts := preload("res://scripts/parts.gd")
const Vessel := preload("res://scripts/vessel.gd")
const W := preload("res://scripts/world.gd")

var main: Node
var world: Node3D
var cam: Camera3D

var active := false
var paused := false
var t := 0.0
var warp := 1.0
var warp_lock := 1.0
var vessel: Vessel = null
var iss = null            # Dictionary (Körper) oder null
var debris: Array = []
var M = null              # laufende Mission
var pred: Dictionary = {}
var pred_at := 0.0
var sas := "hold"
var hold := PI / 2.0
var guide_hd := NAN
var show_guide := false
var auto := false
var cut := false
var lock_engine := false
var max_throttle := 1.0
var countdown := -1.0
var cd_shown := 4
var said_once := {}
var shake := 0.0
var keys_hint: Array = []
var objective := ""
var max_alt := 0.0
var stage_timer := 0.0
var drop_timer := 0.0
var day_was := -1
var landing := {}
var crash := ""
var dock := {}
var iss_heat := 0.0
var last_steer := 0.0
var map_moon := false

# Kamera
var cam_mode := 0
var cam_base := 40.0
var cam_yaw := 0.0
var cam_pitch := 0.1
var cam_dist := 40.0
var cy := 0.0
var cpi := 0.1
var cd := 40.0
var cam_target = null     # anderer Körper als die Rakete
var backdrop := Vector2.INF  # Punkt, der hinter der Rakete im Bild sein soll
var dragging := false
const CAM_MODES := [
	{"name": "Seite", "yaw": 0.0, "pitch": 0.1, "k": 1.0},
	{"name": "Schräg", "yaw": 0.75, "pitch": 0.3, "k": 1.3},
	{"name": "Weit", "yaw": 0.25, "pitch": 0.2, "k": 7.0},
	{"name": "Ganz weit", "yaw": 0.1, "pitch": 0.55, "k": 160.0},
]

# Eingabe (setzt main jedes Bild)
var inp := {"fire": false, "left": false, "right": false, "up": false, "down": false, "warp": false}
var pressed := {}

# Effekte
var smoke: GPUParticles3D
var launch_cloud: GPUParticles3D
var sparks: CPUParticles3D
var smoke_tpl: CPUParticles3D
var nozzle_light: OmniLight3D
var vapor: MeshInstance3D
var streaks: CPUParticles3D
var sci := {}             # Raketenwissenschaft: was schon erklärt wurde + Messwerte

func _ready() -> void:
	smoke = _gpu_smoke(1500, 8.0, 2.0, 6.0, Color(0.95, 0.95, 0.95, 0.75))
	launch_cloud = _gpu_smoke(260, 8.0, 3.0, 13.0, Color(0.97, 0.97, 0.97, 0.85))
	var lpm: ParticleProcessMaterial = launch_cloud.process_material
	lpm.direction = Vector3(0, 1, 0); lpm.spread = 88.0; lpm.flatness = 0.75
	lpm.initial_velocity_min = 15.0; lpm.initial_velocity_max = 45.0; lpm.damping_min = 3.0; lpm.damping_max = 6.0
	sparks = _make_particles(500, 1.0, Color(1.0, 0.6, 0.2, 0.9), 2.0, 1.0, true)
	sparks.damping_min = 2.0; sparks.damping_max = 4.0
	smoke_tpl = _make_particles(8, 1.0, Color.WHITE, 1.0, 1.0)
	nozzle_light = OmniLight3D.new(); nozzle_light.light_color = Color(1.0, 0.62, 0.3); nozzle_light.omni_range = 90.0
	nozzle_light.omni_attenuation = 1.4; nozzle_light.light_energy = 0.0; nozzle_light.shadow_enabled = false
	add_child(nozzle_light)
	# Dampfkegel (beim schnellen Flug durch dichte Luft)
	var vc := CylinderMesh.new(); vc.top_radius = 0.3; vc.bottom_radius = 4.2; vc.height = 5.0; vc.radial_segments = 32; vc.cap_top = false; vc.cap_bottom = false
	var vm := StandardMaterial3D.new(); vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; vm.albedo_color = Color(1, 1, 1, 0.0)
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; vm.cull_mode = BaseMaterial3D.CULL_DISABLED; vm.rim_enabled = false
	vm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	vapor = MeshInstance3D.new(); vapor.mesh = vc; vapor.material_override = vm; vapor.visible = false; vapor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vapor)
	# Geschwindigkeitsstreifen: dünne Striche, die in der Luft stehen bleiben
	streaks = CPUParticles3D.new(); streaks.amount = 90; streaks.lifetime = 0.45; streaks.local_coords = false; streaks.emitting = false
	var bm := BoxMesh.new(); bm.size = Vector3(0.04, 4.0, 0.04)
	var sm2 := StandardMaterial3D.new(); sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm2.albedo_color = Color(1, 1, 1, 0.35); sm2.vertex_color_use_as_albedo = true; bm.material = sm2
	streaks.mesh = bm; streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; streaks.emission_sphere_radius = 22.0
	streaks.gravity = Vector3.ZERO; streaks.particle_flag_align_y = true; streaks.spread = 0.0
	streaks.initial_velocity_min = 0.5; streaks.initial_velocity_max = 1.0
	var sr := Gradient.new(); sr.set_color(0, Color(1, 1, 1, 0)); sr.set_color(1, Color(1, 1, 1, 0)); sr.add_point(0.3, Color(1, 1, 1, 0.22))
	streaks.color_ramp = sr
	streaks.visibility_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	add_child(streaks)

func _gpu_smoke(amount: int, life: float, size0: float, size1: float, col: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.local_coords = false; p.emitting = false
	p.interpolate = true; p.fract_delta = true
	p.visibility_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0); pm.spread = 9.0
	pm.initial_velocity_min = 28.0; pm.initial_velocity_max = 55.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 7.0; pm.damping_max = 12.0
	pm.scale_min = size1 * 0.8; pm.scale_max = size1 * 1.2
	var cv := Curve.new(); cv.add_point(Vector2(0.0, size0 / size1)); cv.add_point(Vector2(0.25, 0.55)); cv.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new(); ct.curve = cv; pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0)); g.set_color(1, Color(col.r * 0.9, col.g * 0.9, col.b * 0.92, 0.0))
	g.add_point(0.04, col); g.add_point(0.45, Color(col.r, col.g, col.b, col.a * 0.55))
	var gt := GradientTexture1D.new(); gt.gradient = g; pm.color_ramp = gt
	pm.angle_min = 0.0; pm.angle_max = 360.0; pm.angular_velocity_min = -12.0; pm.angular_velocity_max = 12.0
	pm.turbulence_enabled = true; pm.turbulence_noise_strength = 3.0; pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.03; pm.turbulence_influence_max = 0.12
	p.process_material = pm
	# dicke Comic-Wolken: weiche Kugeln, die wachsen und am Ende wieder schrumpfen
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 16; sm.rings = 8
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9; m.rim_enabled = true; m.rim = 0.35; m.rim_tint = 0.2
	sm.material = m
	p.draw_pass_1 = sm
	cv.clear_points(); cv.add_point(Vector2(0.0, size0 / size1)); cv.add_point(Vector2(0.3, 0.75)); cv.add_point(Vector2(0.75, 1.0)); cv.add_point(Vector2(1.0, 0.0))
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(0.82, 0.84, 0.88, 1))
	add_child(p)
	return p

func _soft_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.55))
	var tx := GradientTexture2D.new()
	tx.gradient = g; tx.fill = GradientTexture2D.FILL_RADIAL; tx.fill_from = Vector2(0.5, 0.5); tx.fill_to = Vector2(1.0, 0.5)
	tx.width = 64; tx.height = 64
	return tx

func _make_particles(amount: int, life: float, col: Color, size0: float, grow: float, additive := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.local_coords = false; p.emitting = false
	var qm := QuadMesh.new(); qm.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_texture()
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	qm.material = m
	p.mesh = qm
	p.direction = Vector3(0, -1, 0); p.spread = 12.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 25.0; p.initial_velocity_max = 55.0
	p.damping_min = 8.0; p.damping_max = 14.0
	p.scale_amount_min = size0; p.scale_amount_max = size0 * 1.4
	var curve := Curve.new(); curve.add_point(Vector2(0, 0.3)); curve.add_point(Vector2(1, grow)); curve.max_value = grow
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0)); ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.08, col); ramp.add_point(0.5, Color(col.r, col.g, col.b, col.a * 0.5))
	p.color_ramp = ramp
	p.visibility_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	add_child(p)
	return p

# =====================================================================
#  Start / Ende
# =====================================================================
func clear() -> void:
	if vessel:
		vessel.group.queue_free(); vessel = null
	for d in debris:
		if is_instance_valid(d.node):
			d.node.queue_free()
		if d.has("glow") and is_instance_valid(d.glow):
			d.glow.queue_free()
	debris.clear()
	if iss:
		iss.node.queue_free(); iss = null
	world.ship.visible = false
	world.pad_arm.rotation.y = 0.0
	pred = {}; dock = {}; auto = false; cut = false; warp = 1.0; warp_lock = 1.0; sas = "hold"
	said_once = {}; sci = {"q_max": 0.0}; max_alt = 0.0; day_was = -1; cam_target = null; countdown = -1.0; stage_timer = 0.0; drop_timer = 0.0
	max_throttle = 1.0; show_guide = false; guide_hd = NAN; lock_engine = false; iss_heat = 0.0; landing = {}; crash = ""
	smoke.emitting = false; launch_cloud.emitting = false; sparks.emitting = false
	backdrop = Vector2.INF
	keys_hint = []; objective = ""; t = 0.0; P.moon_theta0 = 1.2; map_moon = false
	main.audio.engine(0, 0); main.audio.wind(0, 0)

func new_vessel(design: Dictionary) -> Vessel:
	vessel = Vessel.new(design, self)
	return vessel

func place_on_pad(v: Vessel) -> void:
	v.x = 0.0; v.y = P.R + v.h / 2.0; v.vx = 0.0; v.vy = 0.0; v.hd = PI / 2.0; v.landed = true; v.on_pad = true; hold = v.hd

func place_in_orbit(v: Vessel, phi: float, alt := P.ORBIT_ALT) -> void:
	var r := P.R + alt
	var s := sqrt(P.GM / r)
	v.x = r * cos(phi); v.y = r * sin(phi); v.vx = -s * sin(phi); v.vy = s * cos(phi)
	v.hd = atan2(v.vy, v.vx); v.landed = false; v.on_pad = false; hold = v.hd; sas = "pro"

func set_cam_mode(i: int) -> void:
	cam_mode = i % CAM_MODES.size()
	var m: Dictionary = CAM_MODES[cam_mode]
	cam_yaw = m.yaw; cam_pitch = m.pitch; cam_dist = cam_base * m.k

func snap_cam() -> void:
	cy = cam_yaw; cpi = cam_pitch; cd = cam_dist

func emit_event(name: String, data = null) -> void:
	if M:
		M.on(name, data)

func say(id: String) -> void:
	main.say(id)

func say_once(id: String, key := "") -> bool:
	var k := key if key != "" else id
	if said_once.has(k):
		return false
	said_once[k] = true
	say(id)
	return true

func speaking() -> bool:
	return main.audio.speaking()

# =====================================================================
#  ISS
# =====================================================================
func make_iss_body(theta: float, alt := P.ORBIT_ALT) -> Dictionary:
	var node := build_iss()
	add_child(node)
	var r := P.R + alt
	var v := sqrt(P.GM / r)
	var b := {"node": node, "theta0": theta, "r": r, "w": v / r, "dynamic": false, "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0,
		"mass": 420000.0, "cd_a": 1300.0, "decay": 0.0, "thrust": 0.0, "tug": null, "alive": true}
	iss_rails(b, 0.0)
	return b

func iss_rails(b: Dictionary, tt: float) -> void:
	if b.dynamic:
		return
	var a: float = b.theta0 + b.w * tt
	var v: float = b.w * b.r
	b.x = b.r * cos(a); b.y = b.r * sin(a); b.vx = -v * sin(a); b.vy = v * cos(a)

static func basis_heading(hd: float) -> Basis:
	var yv := Vector3(cos(hd), sin(hd), 0)
	var xv := Vector3(sin(hd), -cos(hd), 0)
	return Basis(xv, yv, Vector3(0, 0, 1))

static func basis_orbit(x: float, y: float, vx: float, vy: float) -> Basis:
	var up := Vector3(x, y, 0).normalized()
	var fw := Vector3(vx, vy, 0).normalized()
	fw = (fw - up * fw.dot(up)).normalized()
	var xa := up.cross(fw)
	return Basis(xa, up, fw)

func iss_visual(b: Dictionary) -> void:
	var n: Node3D = b.node
	n.global_transform = Transform3D(basis_orbit(b.x, b.y, b.vx, b.vy), Vector3(b.x, b.y, 0))
	var s: Vector3 = n.global_transform.basis.inverse() * P.sun_dir()
	var ang := atan2(-s.y, s.z)
	for w in n.get_meta("wings"):
		if is_instance_valid(w) and w.get_parent() and w.get_parent().name == "Panels":
			w.rotation.x = ang

func build_iss() -> Node3D:
	var g := Node3D.new()
	var body := Node3D.new(); body.name = "Body"; g.add_child(body)
	var panels := Node3D.new(); panels.name = "Panels"; g.add_child(panels)
	var grey := W.mat(Color(0.55, 0.58, 0.64), 0.6, 0.3)
	var dark := W.mat(Color(0.17, 0.2, 0.25), 0.55, 0.4)
	var white := W.mat(Color(0.95, 0.96, 0.97), 0.45, 0.1)
	var metal := W.mat(Color(0.73, 0.76, 0.8), 0.3, 0.85)
	var gold := W.mat(Color(0.85, 0.65, 0.23), 0.35, 0.9)
	var panel := W.mat(Color(0.11, 0.2, 0.45), 0.3, 0.6, Color(0.03, 0.06, 0.18))
	body.add_child(W.box(Vector3(104, 2.6, 2.6), grey))
	for i in range(-48, 49, 6):
		var b := W.box(Vector3(0.4, 3.2, 3.2), dark); b.position.x = i; body.add_child(b)
	var wings := []
	for sx in [-1, 1]:
		for k in [38, 50]:
			for sy in [-1, 1]:
				var w := Node3D.new()
				var p := W.box(Vector3(11.5, 34, 0.12), panel); p.position.y = sy * 18.5; w.add_child(p)
				for gy in range(1, 8):
					var line := W.box(Vector3(11.6, 0.15, 0.14), W.mat(Color(0.3, 0.42, 0.72), 0.4, 0.5)); line.position.y = sy * (1.5 + gy * 4.2); w.add_child(line)
				var mast := W.box(Vector3(0.35, 36, 0.35), gold); mast.position.y = sy * 18.0; w.add_child(mast)
				w.position.x = sx * k
				panels.add_child(w); wings.append(w)
	for sx in [-1, 1]:
		var rad := W.box(Vector3(4, 0.15, 14), white); rad.position = Vector3(sx * 18, 0, -8); rad.rotation.x = 0.2; body.add_child(rad)
	for mm in [[-26, -14, 2.1, white], [-14, -4, 2.2, white], [-4, 4, 2.3, white], [4, 15, 2.2, white], [15, 22, 2.1, white], [-38, -26, 2.0, metal]]:
		var c := W.cyl(mm[2], mm[2], mm[1] - mm[0], mm[3]); c.rotation.x = PI / 2.0; c.position = Vector3(0, -3.4, (mm[0] + mm[1]) / 2.0)
		c.set_meta("module", true); body.add_child(c)
	for sx in [-1, 1]:
		var c := W.cyl(2.1, 2.1, 8, white); c.rotation.z = PI / 2.0; c.position = Vector3(sx * 6, -3.4, 0); body.add_child(c)
	var port := W.cyl(0.9, 0.9, 2, metal); port.rotation.x = PI / 2.0; port.position = Vector3(0, -3.4, 23.2); body.add_child(port)
	var ring := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 1.0; tm.outer_radius = 1.32
	ring.mesh = tm; ring.material_override = W.mat(Color(1, 0.82, 0.25), 0.4, 0.0, Color(0.6, 0.45, 0.0))
	ring.rotation.x = PI / 2.0; ring.position = Vector3(0, -3.4, 24.2); body.add_child(ring)
	g.set_meta("wings", wings)
	g.set_meta("port", Vector3(0, -3.4, 24.3))
	return g

# =====================================================================
#  Physik
# =====================================================================
func cam_body():
	if cam_target != null:
		return cam_target
	if vessel != null:
		return vessel
	return iss

func step_vessel(v: Vessel, h: float) -> void:
	if v.landed:
		if v.on_pad and v.throttle > 0.0:
			var fth := v.thrust(1.0, h)
			if fth > v.mass() * P.G0 * 1.02:
				v.landed = false; v.on_pad = false
				emit_event("liftoff")
		return
	var r := sqrt(v.x * v.x + v.y * v.y)
	var alt := r - P.R
	var p := P.rho(alt) / P.RHO0
	v.mass_ = v.mass(); v.cd_a_ = v.cd_a()
	var fth := v.thrust(p, h)
	v.thrust_n = fth
	var a := P.grav(v.x, v.y, t)
	var ax: float = a[0]
	var ay: float = a[1]
	var dm: float = a[2]
	var dx := cos(v.hd)
	var dy := sin(v.hd)
	ax += fth / v.mass_ * dx; ay += fth / v.mass_ * dy
	var rr := P.rho(alt)
	var sp := sqrt(v.vx * v.vx + v.vy * v.vy)
	v.q = 0.5 * rr * sp * sp
	var drag_a := 0.0
	if rr > 0.0:
		var k := 0.5 * rr * sp * v.cd_a_ / v.mass_
		ax -= k * v.vx; ay -= k * v.vy
		drag_a = k * sp
	# gespürte Beschleunigung (ohne Schwerkraft) in g
	var gl := Vector2(fth / v.mass_ * dx, fth / v.mass_ * dy) - Vector2(v.vx, v.vy).normalized() * drag_a
	v.g_load = lerpf(v.g_load, gl.length() / P.G0, 0.05)
	v.g_max = maxf(v.g_max, v.g_load)
	v.vx += ax * h; v.vy += ay * h
	v.x += v.vx * h; v.y += v.vy * h
	if dm < P.RMOON + 2.0:
		crash = "moon"; return
	var rb := sqrt(pow(v.x - dx * v.h / 2.0, 2.0) + pow(v.y - dy * v.h / 2.0, 2.0))
	var rn := sqrt(v.x * v.x + v.y * v.y)
	var vr := (v.x * v.vx + v.y * v.vy) / rn
	if (rb <= P.R or rn - v.h * 0.3 <= P.R) and vr < 0.0:
		var speed := sqrt(v.vx * v.vx + v.vy * v.vy)
		var phi := atan2(v.y, v.x)
		var sea := not P.is_land_at(phi)
		if speed < 30.0 or (v.chute_open > 0.5 and speed < 45.0):
			v.landed = true; v.splashed = sea; v.vx = 0.0; v.vy = 0.0; v.hd = phi
			var rr2 := P.R + v.h / 2.0 - (0.9 if sea else 0.0)
			v.x = cos(phi) * rr2; v.y = sin(phi) * rr2
			landing = {"sea": sea, "speed": speed, "phi": phi}
		else:
			crash = "ground"

func step_body(b: Dictionary, h: float, ex := 0.0, ey := 0.0) -> void:
	var a := P.grav(b.x, b.y, t)
	var ax: float = a[0] + ex
	var ay: float = a[1] + ey
	var r: float = sqrt(b.x * b.x + b.y * b.y)
	var rr := P.rho(r - P.R)
	if rr > 0.0:
		var sp: float = sqrt(b.vx * b.vx + b.vy * b.vy)
		var k: float = 0.5 * rr * sp * b.cd_a / b.mass
		ax -= k * b.vx; ay -= k * b.vy
	if b.get("decay", 0.0) > 0.0:
		ax -= b.decay * b.vx; ay -= b.decay * b.vy
	b.vx += ax * h; b.vy += ay * h
	b.x += b.vx * h; b.y += b.vy * h

func physics(sim_dt: float) -> void:
	var v := vessel
	var h_max := 1.0 / 120.0
	var body = cam_body()
	if body != null:
		var r: float = sqrt(body.x * body.x + body.y * body.y)
		var alt := r - P.R
		var ma := P.moon_angle(t)
		var dm: float = sqrt(pow(body.x - P.RM * cos(ma), 2.0) + pow(body.y - P.RM * sin(ma), 2.0))
		var busy := (v != null and (v.throttle > 0.0 or v.landed)) or alt < P.ATM + 400.0
		for d in debris:
			if d.alive and sqrt(d.x * d.x + d.y * d.y) - P.R < P.ATM + 200.0 and d.age < 400.0:
				busy = true
		if iss != null and iss.dynamic and (iss.thrust != 0.0 or sqrt(iss.x * iss.x + iss.y * iss.y) - P.R < P.ATM + 400.0):
			busy = true
		if not busy:
			h_max = clampf(0.004 * minf(sqrt(pow(r, 3.0) / P.GM), sqrt(pow(dm, 3.0) / P.GMM)), 1.0 / 60.0, 4.0)
	var n := mini(1500, int(ceil(sim_dt / h_max)))
	n = maxi(n, 1)
	var h := sim_dt / n
	for i in n:
		if v != null and dock.is_empty():
			step_vessel(v, h)
		if iss != null:
			if iss.dynamic:
				if iss.alive:
					var ex := 0.0
					var ey := 0.0
					if iss.thrust != 0.0:
						var sp: float = sqrt(iss.vx * iss.vx + iss.vy * iss.vy)
						ex = iss.thrust * iss.vx / sp; ey = iss.thrust * iss.vy / sp
					step_body(iss, h, ex, ey)
			else:
				iss_rails(iss, t + h)
		for d in debris:
			if d.alive:
				step_body(d, h)
				d.age += h
				if sqrt(d.x * d.x + d.y * d.y) <= P.R:
					d.alive = false; d.landed_at = Vector2(d.x, d.y); _debris_landed(d)
		t += h
		if crash != "" or not landing.is_empty():
			break

func add_debris(node: Node3D, x: float, y: float, vx: float, vy: float, hd: float, w: float, cd_a: float, mass: float, kind: String) -> Dictionary:
	var gt := node.global_transform
	if node.get_parent():
		node.get_parent().remove_child(node)
	add_child(node)
	var phys := Transform3D(basis_heading(hd), Vector3(x, y, 0))
	var d := {"node": node, "x": x, "y": y, "vx": vx, "vy": vy, "hd": hd, "w": w, "cd_a": cd_a, "mass": mass, "kind": kind,
		"age": 0.0, "alive": true, "heat": 0.0, "spin": 0.0, "survive": true, "burn": -1.0, "local": phys.affine_inverse() * gt, "sea": true}
	node.global_transform = gt
	debris.append(d)
	return d

func _debris_landed(d: Dictionary) -> void:
	var sea := not P.is_land_at(atan2(d.y, d.x))
	d.sea = sea
	var dist := Vector2(cam.global_position.x - d.x, cam.global_position.y - d.y).length()
	if dist < 30000.0:
		splash_fx(d.x, d.y, sea, 3.0 if d.kind == "iss" else 1.4)
	if dist < 6000.0 and sea:
		main.audio.sfx("splash")
	if d.kind != "iss":
		d.node.visible = false
	emit_event("debris", d)

func splash_fx(x: float, y: float, sea: bool, k := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.explosiveness = 0.9; p.amount = int(80 * k); p.lifetime = 3.0; p.local_coords = false
	p.mesh = smoke_tpl.mesh
	p.direction = Vector3(0, 1, 0); p.spread = 50.0
	p.initial_velocity_min = 10.0 * k; p.initial_velocity_max = 35.0 * k
	p.gravity = Vector3(0, -12, 0)
	p.damping_min = 1.0; p.damping_max = 2.0
	p.scale_amount_min = 2.0 * k; p.scale_amount_max = 4.0 * k
	var col := Color(0.92, 0.96, 1.0, 0.85) if sea else Color(0.6, 0.5, 0.38, 0.75)
	var ramp := Gradient.new(); ramp.set_color(0, col); ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	add_child(p)
	var u := Vector3(x, y, 0).normalized()
	p.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, u)), u * P.R)
	p.emitting = true
	get_tree().create_timer(4.0).timeout.connect(p.queue_free)

# =====================================================================
#  Stufen, Prüfungen, Ereignisse
# =====================================================================
func drop_boosters() -> void:
	var v := vessel
	if not v.boost:
		return
	v.boost = false
	var sg: Node3D = v.stage_nodes[0]
	if not sg.has_meta("boosters"):
		return
	var bg: Node3D = sg.get_meta("boosters")
	for b in bg.get_children():
		var wp: Vector3 = b.global_transform * Vector3(0, 4.5, 0)
		var dvx := wp.x - v.x
		var dvy := wp.y - v.y
		var ol := maxf(0.001, sqrt(dvx * dvx + dvy * dvy))
		var d := Vector2(cos(v.hd), sin(v.hd))
		for fl in b.get_children():
			if fl.has_meta("mat"):
				fl.visible = false
		add_debris(b, wp.x, wp.y, v.vx + dvx / ol * 6.0 - d.x * 2.0, v.vy + dvy / ol * 6.0 - d.y * 2.0, v.hd, randf_range(-0.4, 0.4), 4.0, 700.0, "booster")
	main.audio.sfx("clack")
	shake = maxf(shake, 0.5)
	emit_event("boosters")

func do_stage() -> void:
	var v := vessel
	if v == null or v.capsule_only() or v.landed or not dock.is_empty():
		return
	var last := v.s == v.st.size() - 1
	if v.boost:
		v.boost = false
		var sg0: Node3D = v.stage_nodes[0]
		if sg0.has_meta("boosters"):
			var bg: Node3D = sg0.get_meta("boosters")
			for b in bg.get_children():
				var wp: Vector3 = b.global_transform * Vector3(0, 4.5, 0)
				add_debris(b, wp.x, wp.y, v.vx, v.vy, v.hd, randf_range(-0.4, 0.4), 4.0, 700.0, "booster")
	var sg: Node3D = v.stage_nodes[v.s]
	var sd: Dictionary = v.st[v.s]
	var d := Vector2(cos(v.hd), sin(v.hd))
	var bottom := Vector2(v.x, v.y) - d * v.h / 2.0
	var sh: float = sd.h
	var c: Vector2 = bottom + d * sh / 2.0
	var fl: Node3D = sg.get_meta("flame")
	fl.visible = false
	add_debris(sg, c.x, c.y, v.vx - d.x * 4.0, v.vy - d.y * 4.0, v.hd, randf_range(-0.15, 0.15), 0.6 * PI * Parts.RC * Parts.RC, (sd.dry + sd.fuel) * 1000.0, "stage")
	v.s += 1
	v.relayout()
	var nb: Vector2 = bottom + d * sh
	v.x = nb.x + d.x * v.h / 2.0; v.y = nb.y + d.y * v.h / 2.0
	main.audio.sfx("clack")
	shake = maxf(shake, 0.5)
	burst_fx(Vector3(nb.x, nb.y, 0), 1.3)
	main.ui.big_msg("KLACK!", true)
	emit_event("capsule" if last else "staging")

func post_checks(dt: float) -> void:
	var v := vessel
	if v == null or not dock.is_empty():
		return
	var r := sqrt(v.x * v.x + v.y * v.y)
	var alt := r - P.R
	var vr := (v.x * v.vx + v.y * v.vy) / r
	var sp := sqrt(v.vx * v.vx + v.vy * v.vy)
	max_alt = maxf(max_alt, alt)
	if alt > P.SPACE_ALT and not said_once.has("evt_space"):
		said_once["evt_space"] = true
		emit_event("space")
	if v.boost and v.st[0].b_fuel <= 0.0:
		drop_boosters()
	if not v.capsule_only() and v.throttle > 0.0 and v.st[v.s].fuel <= 0.0 and v.s < v.st.size() - 1:
		stage_timer += dt
		if stage_timer > 0.35:
			stage_timer = 0.0; do_stage()
	else:
		stage_timer = 0.0
	if not v.capsule_only() and not v.landed and alt < P.ATM + 1200.0 and vr < -15.0 and (sp > 160.0 or v.all_empty()) and v.throttle == 0.0:
		drop_timer += dt
		if drop_timer > 0.7:
			drop_timer = 0.0; do_stage()
	else:
		drop_timer = 0.0
	if v.capsule_only() and not v.chute and not v.landed and alt < 1400.0 and vr < 0.0 and sp < 260.0:
		v.chute = true
		main.audio.sfx("chute")
		cam_dist = maxf(cam_dist, 90.0); cam_pitch = 0.02
		emit_event("chute")
	if not landing.is_empty():
		var L := landing
		landing = {}
		if L.sea:
			main.audio.sfx("splash"); splash_fx(v.x, v.y, true, 1.5); world.place_ship_near(v.x, v.y)
		else:
			main.audio.sfx("thud"); splash_fx(v.x, v.y, false, 1.0)
		shake = 1.0
		emit_event("landed", L)
	if crash != "":
		var c := crash
		crash = ""
		main.audio.sfx("boom"); shake = 3.0
		splash_fx(v.x, v.y, not P.is_land_at(atan2(v.y, v.x)), 2.5)
		v.group.visible = false; v.landed = true; v.vx = 0.0; v.vy = 0.0; v.throttle = 0.0
		emit_event("crash", c)
	_science(v, alt, vr, sp, dt)
	if not v.landed and alt > P.ATM:
		var day := 1 if (v.x * P.sun_dir().x + v.y * P.sun_dir().y) / r > -0.05 else 0
		if day_was >= 0 and day != day_was:
			emit_event("sunrise" if day == 1 else "night")
		day_was = day

# =====================================================================
#  Raketenwissenschaft: Mira erklärt, was gerade passiert
# =====================================================================
func _sci(id: String, cond: bool) -> void:
	if not cond or sci.has(id) or speaking():
		return
	if Time.get_ticks_msec() / 1000.0 - sci.get("last", -100.0) < 4.0:
		return
	sci[id] = true; sci.last = Time.get_ticks_msec() / 1000.0
	say(id)

func _science(v: Vessel, alt: float, vr: float, sp: float, dt: float) -> void:
	if M == null or M.id == "issd" or v.landed:
		return
	var firing := v.firing()
	sci.burn_t = sci.get("burn_t", 0.0) + dt if firing else 0.0
	# Max Q: der stärkste Luftdruck beim Aufstieg
	if vr > 0.0 and firing:
		sci.q_max = maxf(sci.get("q_max", 0.0), v.q)
	if not sci.has("sci_maxq") and vr > 0.0 and sci.get("q_max", 0.0) > 6000.0 and v.q < sci.q_max * 0.85:
		if not speaking():
			sci["sci_maxq"] = true; sci.last = Time.get_ticks_msec() / 1000.0
			say("sci_maxq"); main.ui.big_msg("MAX Q!", true); shake = maxf(shake, 0.8)
	_sci("sci_newton", firing and sci.burn_t > 3.0 and alt > 30.0)
	_sci("sci_g", firing and v.g_load > 2.2)
	var up := atan2(v.y, v.x)
	_sci("sci_turn", firing and alt > 900.0 and absf(P.ang_diff(v.hd, up)) > 0.35 and vr > 0.0)
	_sci("sci_light", firing and v.s == 0 and not v.capsule_only() and v.st[0].fuel < v.st[0].fuel0 * 0.35)
	if firing:
		sci.was_burning = sci.get("burn_t", 0.0) > 8.0 or sci.get("was_burning", false)
	_sci("sci_meco", not firing and sci.get("was_burning", false) and alt > 3000.0 and vr > 0.0)
	_sci("sci_vac", firing and alt > P.ATM + 500.0)
	_sci("sci_blackout", v.heat > 0.6)
	var el := P.elements(v.x, v.y, v.vx, v.vy)
	if not el.esc and el.pe > P.ATM and not firing:
		sci.orbit_t = sci.get("orbit_t", 0.0) + dt
	_sci("sci_weightless", sci.get("orbit_t", 0.0) > 25.0)

## Rauch- und Funkenstoß (z. B. bei der Stufentrennung)
func burst_fx(pos: Vector3, k := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.explosiveness = 0.95; p.amount = int(40 * k); p.lifetime = 1.6; p.local_coords = false
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 12; sm.rings = 6
	var m := StandardMaterial3D.new(); m.vertex_color_use_as_albedo = true; m.roughness = 0.9; sm.material = m
	p.mesh = sm; p.direction = Vector3(0, 1, 0); p.spread = 180.0
	p.initial_velocity_min = 4.0 * k; p.initial_velocity_max = 12.0 * k; p.gravity = Vector3.ZERO
	p.damping_min = 3.0; p.damping_max = 6.0
	p.scale_amount_min = 1.0 * k; p.scale_amount_max = 2.2 * k
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.4)); cv.add_point(Vector2(0.3, 1.0)); cv.add_point(Vector2(1, 0.0)); p.scale_amount_curve = cv
	var g := Gradient.new(); g.set_color(0, Color(1, 0.85, 0.4)); g.set_color(1, Color(0.85, 0.87, 0.9)); p.color_ramp = g
	add_child(p); p.global_position = pos; p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)

# =====================================================================
#  Hilfen: Leitstern und Bordcomputer
# =====================================================================
func ascent_guide(v: Vessel, target := P.ORBIT_ALT) -> Dictionary:
	var r := sqrt(v.x * v.x + v.y * v.y)
	var alt := r - P.R
	var up := atan2(v.y, v.x)
	var el := P.elements(v.x, v.y, v.vx, v.vy)
	var vr := (v.x * v.vx + v.y * v.vy) / r
	if not el.esc and el.ap >= target - 300.0 and alt > P.ATM * 0.8:
		var phase := "orbit" if el.pe > P.ATM + 1500.0 else ("coast" if vr > 25.0 else "circ")
		return {"hd": up + PI / 2.0 + clampf(vr * 0.03, -0.5, 0.6), "phase": phase, "el": el}
	var k := pow(clampf((alt - 150.0) / (P.ATM * 2.2), 0.0, 1.0), 0.55)
	var hd := up + k * PI / 2.0 * 0.98
	var pro := atan2(v.vy, v.vx)
	var sp := sqrt(v.vx * v.vx + v.vy * v.vy)
	if alt > 1500.0 and sp > 50.0:
		var d := P.ang_diff(pro, hd)
		if absf(d) < 0.35:
			hd += d * 0.5
	return {"hd": hd, "phase": "ascent", "el": el}

func autopilot_ascent(v: Vessel) -> float:
	var g := ascent_guide(v)
	sas = "guide"; guide_hd = g.hd
	match g.phase:
		"ascent":
			return 1.0 if g.el.ap < P.ORBIT_ALT - 300.0 else 0.0
		"coast":
			var tta := P.time_to_apo(v.x, v.y, v.vx, v.vy)
			return 1.0 if (tta < 12.0 or g.el.ap < P.ORBIT_ALT - 500.0) else 0.0
		"circ":
			return 1.0 if (g.el.pe < P.ORBIT_ALT - 2500.0 and g.el.ap < P.ORBIT_ALT + 4000.0) else 0.0
	return 0.0

func attitude(v: Vessel, dt: float) -> void:
	if v.landed:
		if v.on_pad:
			v.hd = PI / 2.0
		return
	var rate := 1.1
	var up := atan2(v.y, v.x)
	var pro := atan2(v.vy, v.vx)
	var sp := sqrt(v.vx * v.vx + v.vy * v.vy)
	if (inp.left or inp.right) and not v.capsule_only():
		v.hd += (1.0 if inp.right else -1.0) * rate * dt
		sas = "hold"; hold = v.hd; auto = false; last_steer = Time.get_ticks_msec() / 1000.0
		return
	if show_guide and not is_nan(guide_hd) and sas == "hold" and Time.get_ticks_msec() / 1000.0 - last_steer > 2.0 and sqrt(v.x * v.x + v.y * v.y) - P.R > 250.0:
		sas = "guide"
	var target := NAN
	if v.capsule_only():
		if v.chute:
			target = up
		elif sp > 40.0 and sqrt(v.x * v.x + v.y * v.y) - P.R < P.ATM + 3000.0:
			target = pro + PI
	else:
		match sas:
			"pro":
				if sp > 3.0: target = pro
			"retro":
				if sp > 3.0: target = pro + PI
			"guide":
				target = guide_hd
			"hold":
				target = hold
	if not is_nan(target):
		v.hd += clampf(P.ang_diff(target, v.hd), -rate * dt, rate * dt)

func start_countdown() -> void:
	if countdown >= 0.0 or vessel == null or not vessel.on_pad:
		return
	countdown = 3.99; cd_shown = 4; lock_engine = true

func _countdown_tick(dt: float) -> void:
	if countdown < 0.0:
		return
	countdown -= dt
	var n := int(ceil(countdown))
	if n != cd_shown and n > 0:
		cd_shown = n
		main.ui.big_msg(str(n))
		main.audio.sfx("beep"); say("c%d" % n)
	if countdown <= 0.0:
		countdown = -1.0; lock_engine = false
		main.ui.big_msg("START!", true)
		main.audio.sfx("beep_hi"); main.audio.sfx("ignite"); say("liftoff")
		world.pad_arm.rotation.y = 1.2; shake = 1.5
		emit_event("go")

func warp_cap() -> float:
	var v := vessel
	var b = cam_body()
	if b == null:
		return 1.0
	if not dock.is_empty() or countdown >= 0.0 or (v != null and v.landed and v.on_pad):
		return 1.0
	var r: float = sqrt(b.x * b.x + b.y * b.y)
	var alt := r - P.R
	var ma := P.moon_angle(t)
	var dm: float = sqrt(pow(b.x - P.RM * cos(ma), 2.0) + pow(b.y - P.RM * sin(ma), 2.0))
	var cap := 100.0
	if v != null and v.throttle > 0.0:
		cap = 2.0
	elif alt < P.ATM:
		cap = 1.0 if (v != null and v.landed) else 4.0
	elif dm < 25000.0:
		cap = 10.0
	elif dm < 45000.0:
		cap = 30.0
	elif dm < 120000.0:
		cap = 100.0
	else:
		cap = (5000.0 if r > 200000.0 else 1000.0) if r > 120000.0 else 100.0
	var vr: float = (b.x * b.vx + b.y * b.vy) / r
	if alt > P.ATM and alt < P.ATM + 2500.0 and vr < -5.0:
		cap = minf(cap, 10.0)
	if M:
		cap = minf(cap, M.warp_cap())
	return cap

# =====================================================================
#  Pro Bild
# =====================================================================
func frame(dt: float) -> void:
	var v := vessel
	_countdown_tick(dt)
	if v != null and dock.is_empty():
		var want: bool = inp.fire and not lock_engine
		if cut:
			if not inp.fire:
				cut = false
			want = false
		if auto and (not v.landed or (v.on_pad and countdown < 0.0 and not lock_engine)):
			var a: float = M.auto_throttle(v) if M and M.has_auto() else autopilot_ascent(v)
			want = a > 0.0 and not lock_engine
		v.throttle = max_throttle if (want and (not v.capsule_only()) and (not v.landed or v.on_pad)) else 0.0
		attitude(v, dt)
	if M:
		M.update(dt)
	var cap := warp_cap()
	var auto_w: bool = auto and M != null and M.auto_warp()
	var wt: float = cap if (inp.warp or auto_w) else minf(warp_lock, cap)
	if warp < wt:
		warp = minf(wt, warp * (1.0 + 2.5 * dt) + dt * 2.0)
	else:
		warp = wt
	if not dock.is_empty():
		dock_update(dt)
	else:
		physics(dt * warp)
	post_checks(dt)
	# Vorausschau
	var now := Time.get_ticks_msec() / 1000.0
	var body = null
	if v != null and not v.landed and dock.is_empty():
		body = v
	elif iss != null and iss.dynamic:
		body = iss
	var period := 0.06 if ((v != null and v.throttle > 0.0) or (iss != null and iss.thrust != 0.0)) else 0.16
	if body != null and now - pred_at > period:
		pred_at = now
		var opts: Dictionary = M.pred_opts() if M else {}
		if body == v:
			v.mass_ = v.mass(); v.cd_a_ = v.cd_a()
			pred = P.predict(v.x, v.y, v.vx, v.vy, t, v.cd_a_, v.mass_, opts)
		else:
			pred = P.predict(body.x, body.y, body.vx, body.vy, t, body.cd_a, body.mass, opts)
	elif body == null:
		pred = {}
	# Darstellung
	if v != null:
		vessel_visual(v, dt)
	if iss != null:
		iss_visual(iss)
	debris_visual(dt)
	shake = maxf(0.0, shake - dt * 1.5)
	if v != null and not v.landed:
		shake = maxf(shake, clampf(v.q / 40000.0, 0.0, 0.5) + v.heat * 0.5 + (0.5 if v.throttle > 0.0 and sqrt(v.x * v.x + v.y * v.y) - P.R < 300.0 else 0.0))
	if v != null:
		var alt := sqrt(v.x * v.x + v.y * v.y) - P.R
		main.audio.engine(1.0 if v.firing() else 0.0, P.rho(alt) / P.RHO0)
		main.audio.wind(0.0 if v.landed else v.q, v.heat)
	elif iss != null:
		main.audio.engine(0.8 if iss.thrust != 0.0 else 0.0, 0.0)
		main.audio.wind(0.0, iss_heat)
	update_camera(dt)

func vessel_visual(v: Vessel, dt: float) -> void:
	var g := v.group
	var alt := sqrt(v.x * v.x + v.y * v.y) - P.R
	var p := P.rho(alt) / P.RHO0
	if dock.is_empty():
		var hd := v.hd
		var pos := Vector3(v.x, v.y, 0)
		if v.landed and v.splashed:
			var tt := Time.get_ticks_msec() / 1000.0
			pos += Vector3(v.x, v.y, 0).normalized() * sin(tt / 0.7) * 0.25
			hd += sin(tt / 0.9) * 0.06
		g.global_transform = Transform3D(basis_heading(hd), pos)
	# Flammen
	for i in v.stage_nodes.size():
		var sg: Node3D = v.stage_nodes[i]
		if not is_instance_valid(sg) or i < v.s:
			continue
		var fl: Node3D = sg.get_meta("flame")
		var on: bool = i == v.s and v.throttle > 0.0 and v.st[i].fuel > 0.0
		fl.visible = on
		var bm: StandardMaterial3D = sg.get_meta("bell_mat")
		bm.emission_energy_multiplier = lerpf(bm.emission_energy_multiplier, 2.5 if on else 0.0, minf(1.0, dt * (4.0 if on else 0.5)))
		if on:
			var e: Dictionary = v.st[i].e
			var vac := 1.0 - p
			var fk := randf_range(0.9, 1.1)
			fl.scale = Vector3(e.bell * (1.0 + vac * 1.3), (5.0 + 9.0 * e.thrust / 100.0) * (1.0 + vac * 1.2) * fk, e.bell * (1.0 + vac * 1.3))
			fl.get_meta("mat").set_shader_parameter("vac", clampf(vac, 0.0, 1.0))
		if i == 0 and sg.has_meta("boosters") and v.s == 0:
			var bg: Node3D = sg.get_meta("boosters")
			for bf in bg.get_meta("flames"):
				if is_instance_valid(bf) and bf.is_inside_tree() and bf.get_parent().get_parent() == bg:
					var bon: bool = v.boost and v.throttle > 0.0 and v.st[0].b_fuel > 0.0
					bf.visible = bon
					if bon:
						bf.scale = Vector3(0.6, randf_range(9.0, 11.0), 0.6)
	# Licht an der Düse
	var dvl := Vector2(cos(v.hd), sin(v.hd))
	var nzp := Vector2(v.x, v.y) - dvl * (v.h / 2.0 + 4.0)
	nozzle_light.global_position = Vector3(nzp.x, nzp.y, 0)
	nozzle_light.light_energy = (randf_range(5.0, 8.0) * (1.0 - 0.6 * (1.0 - p)) if v.firing() else 0.0)
	# Rauch
	var firing := v.firing() and warp <= 4.0
	var dvec := Vector2(cos(v.hd), sin(v.hd))
	var bottom := Vector2(v.x, v.y) - dvec * (v.h / 2.0 + 3.0)
	smoke.emitting = firing and p > 0.02
	if smoke.emitting:
		smoke.global_transform = Transform3D(basis_heading(v.hd), Vector3(bottom.x, bottom.y, 0))
	launch_cloud.emitting = firing and alt < 70.0
	if launch_cloud.emitting:
		var u := Vector3(v.x, v.y, 0).normalized()
		launch_cloud.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, u)), u * (P.R + 3.0))
	var sp := sqrt(v.vx * v.vx + v.vy * v.vy)
	# Dampfkegel um Max Q
	var vap := 0.0
	if not v.landed and dock.is_empty() and warp <= 4.0:
		vap = smoothstep(200.0, 300.0, sp) * (1.0 - smoothstep(330.0, 430.0, sp)) * clampf(P.rho(alt) * 6.0, 0.0, 1.0)
	vapor.visible = vap > 0.02
	if vapor.visible:
		var vd := Vector2(v.vx, v.vy).normalized()
		var ang := atan2(vd.y, vd.x)
		vapor.global_transform = Transform3D(basis_heading(ang) * Basis.from_scale(Vector3.ONE * randf_range(0.95, 1.05)), Vector3(v.x, v.y, 0) + Vector3(vd.x, vd.y, 0) * (v.h * 0.15))
		(vapor.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, vap * 0.45)
	# Geschwindigkeitsstreifen in der Luft
	streaks.emitting = not v.landed and dock.is_empty() and sp > 250.0 and P.rho(alt) > 0.02 and warp <= 4.0
	if streaks.emitting:
		var vd2 := Vector2(v.vx, v.vy).normalized()
		streaks.global_transform = Transform3D(basis_heading(atan2(vd2.y, vd2.x)), Vector3(v.x, v.y, 0) + Vector3(vd2.x, vd2.y, 0) * 30.0)
		streaks.direction = Vector3(0, -1, 0)
	# Hitze beim Wiedereintritt
	var hq := sqrt(P.rho(alt)) * sp * sp * sp
	v.heat = 0.0 if v.landed else clampf((hq - 0.8e7) / 1.5e7, 0.0, 1.0)
	v.plasma.visible = v.heat > 0.02
	sparks.emitting = v.heat > 0.15 and warp <= 4.0
	if v.plasma.visible:
		var rel := atan2(v.vy, v.vx) - v.hd
		var front := Vector3(-sin(rel), cos(rel), 0) * v.h * 0.35
		var sc := Vector3(Parts.RC * (1.5 + v.heat), 6.0 + v.heat * 22.0, Parts.RC * (1.5 + v.heat))
		var fwd := Vector3(-sin(rel), cos(rel), 0)
		v.plasma.transform = Transform3D(Basis(Vector3(0, 0, 1), rel) * Basis.from_scale(sc), front - fwd * (sc.y * 0.5 - 2.0))
		v.plasma.material_override.set_shader_parameter("power", v.heat)
	if sparks.emitting:
		var va := atan2(v.vy, v.vx)
		sparks.global_transform = Transform3D(basis_heading(va + PI), Vector3(v.x, v.y, 0))
		sparks.initial_velocity_min = 20.0; sparks.initial_velocity_max = 60.0
		sparks.direction = Vector3(0, 1, 0)
	# Fallschirm
	var ch: Node3D = v.cap.get_meta("chute")
	if v.chute:
		ch.visible = true
		v.chute_open = minf(1.0, v.chute_open + dt / 3.0)
		var s := 0.15 + 0.85 * smoothstep(0.0, 1.0, v.chute_open)
		ch.scale = Vector3(s, 0.4 + 0.6 * s, s)
		ch.rotation.z = sin(Time.get_ticks_msec() / 800.0) * 0.05
		if v.landed and v.splashed:
			ch.scale.y = maxf(0.05, ch.scale.y * 0.3)
	else:
		ch.visible = false

func debris_visual(dt: float) -> void:
	for d in debris:
		if not d.alive:
			continue
		d.spin += d.w * dt * minf(warp, 4.0)
		var n: Node3D = d.node
		n.global_transform = Transform3D(basis_heading(d.hd + d.spin), Vector3(d.x, d.y, 0)) * d.local
		var alt: float = sqrt(d.x * d.x + d.y * d.y) - P.R
		var sp: float = sqrt(d.vx * d.vx + d.vy * d.vy)
		d.heat = clampf((sqrt(P.rho(alt)) * sp * sp * sp - 0.8e7) / 1.5e7, 0.0, 1.0)
		# glühender Schweif
		if d.heat > 0.05 and warp <= 4.0:
			if not d.has("glow"):
				d.glow = Parts.make_plasma(); add_child(d.glow)
			var gl: MeshInstance3D = d.glow
			gl.visible = true
			var va: float = atan2(d.vy, d.vx)
			var big := 2.5 if d.kind == "iss" else 1.0
			var ln: float = (8.0 + d.heat * 30.0) * big
			gl.global_transform = Transform3D(basis_heading(va) * Basis.from_scale(Vector3(2.5 * big, ln, 2.5 * big)), Vector3(d.x, d.y, 0) - Vector3(cos(va), sin(va), 0) * (ln * 0.5 - 2.0))
			gl.material_override.set_shader_parameter("power", d.heat)
		elif d.has("glow"):
			d.glow.visible = false
		if d.burn >= 0.0:
			d.burn -= dt * d.heat * 0.5
			if d.burn <= 0.0 and d.heat > 0.0:
				d.alive = false; n.visible = false
				if d.has("glow"):
					d.glow.visible = false
		if d.age > 2400.0 and Vector2(d.x - cam.global_position.x, d.y - cam.global_position.y).length() > 100000.0:
			d.alive = false; n.visible = false

# =====================================================================
#  Kamera
# =====================================================================
func update_camera(dt: float) -> void:
	var k := 1.0 - exp(-dt * 4.0)
	cy += P.ang_diff(cam_yaw, cy) * k
	cpi += (cam_pitch - cpi) * k
	cd *= exp(log(cam_dist / cd) * k)
	if not dock.is_empty():
		_dock_camera(); return
	var b = cam_body()
	if b == null:
		return
	var tx: float = b.x
	var ty: float = b.y
	var r := sqrt(tx * tx + ty * ty)
	var u := Vector3(tx / r, ty / r, 0)
	var e := Vector3(-u.y, u.x, 0)
	var n := Vector3(0, 0, 1)
	var auto_p := 0.0
	if cam_mode <= 1 and not dragging:
		auto_p = 0.42 * smoothstep(P.ATM * 0.6, P.ATM * 3.0, r - P.R) * (1.0 - smoothstep(120000.0, 200000.0, r))
	var pitch := clampf(cpi + auto_p, -1.4, 1.45)
	var off := (n * (-cos(cy) * cos(pitch)) + e * (sin(cy) * cos(pitch)) + u * sin(pitch)) * cd
	var target := Vector3(tx, ty, 0)
	var pos := target + off
	if backdrop != Vector2.INF:
		var bdir := (Vector2(tx, ty) - backdrop).normalized()
		pos = target + Vector3(bdir.x, bdir.y, 0.35) * cd
	var pr := pos.length()
	if pr < P.R + 3.0:
		pos = pos * ((P.R + 3.0) / pr)
	if shake > 0.0:
		var s := shake * minf(1.0, cd / 40.0)
		pos += Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * s
	cam.look_at_from_position(pos, target, u)
	cam.near = clampf(cd * 0.01, 0.2, 50.0)

func _dock_camera() -> void:
	var nd: Node3D = iss.node
	var q := nd.global_transform.basis
	var port: Vector3 = nd.get_meta("port")
	var nose: Vector3 = dock.rel + port
	var cam_local := nose + Vector3(0, 4.2, 19)
	var pos := nd.global_transform * cam_local
	var look := nd.global_transform * port
	cam.look_at_from_position(pos, look, Vector3(iss.x, iss.y, 0).normalized())
	cam.near = 0.2

# =====================================================================
#  Andocken
# =====================================================================
func start_dock() -> void:
	dock = {"rel": Vector3((1.0 if randf() < 0.5 else -1.0) * 3.0, -2.0, 55.0), "vel": Vector3.ZERO, "done": false}

func dock_update(dt: float) -> void:
	var v := vessel
	iss_rails(iss, t + dt); t += dt; iss_visual(iss)
	if not dock.done:
		var tx := (1.0 if inp.right else 0.0) - (1.0 if inp.left else 0.0)
		var ty := (1.0 if inp.up else 0.0) - (1.0 if inp.down else 0.0)
		var tz := -2.2 if inp.fire else (-0.25 if dock.rel.z > 6.0 else 0.0)
		var k := 1.0 - exp(-dt * 2.5)
		var vel: Vector3 = dock.vel
		vel.x += (tx * 1.4 - vel.x) * k; vel.y += (ty * 1.4 - vel.y) * k; vel.z += (tz - vel.z) * k
		dock.vel = vel
		var rel: Vector3 = dock.rel + vel * dt
		rel.x = clampf(rel.x, -12.0, 12.0); rel.y = clampf(rel.y, -12.0, 12.0)
		dock.rel = rel
		v.throttle = 0.2 if inp.fire else 0.0
		if rel.z <= 0.15:
			var ok := absf(rel.x) < 0.8 and absf(rel.y) < 0.8
			var slow := vel.length() < 2.6
			if ok and slow:
				dock.done = true; dock.rel = Vector3.ZERO; dock.vel = Vector3.ZERO
				main.audio.sfx("dock"); shake = 0.6
				emit_event("docked")
			else:
				dock.rel = Vector3(rel.x, rel.y, 3.0); dock.vel = Vector3(vel.x, vel.y, 1.2)
				main.audio.sfx("thud"); say("dock2" if ok else "dock3")
	# Kapsel vor den Andockring setzen
	var nd: Node3D = iss.node
	var port: Vector3 = nd.get_meta("port")
	var nose: Vector3 = nd.global_transform * (dock.rel + port)
	var dir_w: Vector3 = nd.global_transform.basis * Vector3(0, 0, -1)
	var c: Vector3 = nose - dir_w * v.h / 2.0
	v.x = c.x; v.y = c.y; v.vx = iss.vx; v.vy = iss.vy
	var b: Basis = nd.global_transform.basis * Basis(Vector3(1, 0, 0), -PI / 2.0)
	v.group.global_transform = Transform3D(b, c)
