extends RefCounted
## Raketenteile, Baupläne, Werte (Reichweite, Abheben) und 3D-Modelle.

const P := preload("res://scripts/phys.gd")
const W := preload("res://scripts/world.gd")

const CAPSULE_MASS := 1.2
const CAPSULE_H := 2.9
const TANK_DRY := 0.25
const TANK_FUEL := 2.0
const TANK_H := 3.2
const DEC_MASS := 0.1
const DEC_H := 0.45
const FINS_MASS := 0.1
const RC := 1.25
const ENGINES := {
	"small": {"mass": 0.3, "thrust": 70.0, "isp_sl": 70.0, "isp_vac": 80.0, "h": 1.5, "bell": 0.7, "name": "Klein"},
	"big": {"mass": 1.0, "thrust": 230.0, "isp_sl": 75.0, "isp_vac": 85.0, "h": 2.1, "bell": 1.05, "name": "Groß"},
	"vac": {"mass": 0.3, "thrust": 55.0, "isp_sl": 45.0, "isp_vac": 105.0, "h": 2.4, "bell": 1.15, "name": "Weltraum"},
}
const BOOSTER := {"dry": 0.35, "fuel": 2.2, "thrust": 110.0, "isp_sl": 62.0, "isp_vac": 68.0, "r": 0.62, "h": 7.6}
const PRESETS := {
	"hop": {"color": 0, "stages": [{"tanks": 1, "engine": "small", "boosters": 0, "fins": true}]},
	"orbit": {"color": 1, "stages": [{"tanks": 3, "engine": "big", "boosters": 0, "fins": true}, {"tanks": 1, "engine": "vac", "boosters": 0, "fins": false}]},
	"moon": {"color": 2, "stages": [{"tanks": 4, "engine": "big", "boosters": 2, "fins": true}, {"tanks": 2, "engine": "vac", "boosters": 0, "fins": false}]},
}
const NEED := {"space": 420.0, "orbit": 1150.0, "moon": 1560.0}
const STAGE_COLORS := [Color(0.9, 0.22, 0.27), Color(0.18, 0.44, 0.88), Color(0.18, 0.75, 0.44), Color(1.0, 0.72, 0.01), Color(0.54, 0.36, 0.96), Color(0.1, 0.1, 0.12)]
const COLOR_NAMES := ["Rot", "Blau", "Grün", "Gelb", "Lila", "Schwarz"]

static func stage_data(d: Dictionary) -> Array:
	var out := []
	for s in d.stages:
		var e: Dictionary = ENGINES[s.engine]
		var nb: int = s.get("boosters", 0)
		out.append({
			"tanks": s.tanks, "e": e, "engine": s.engine,
			"dry": s.tanks * TANK_DRY + e.mass + DEC_MASS + (FINS_MASS if s.get("fins", false) else 0.0),
			"fuel": s.tanks * TANK_FUEL, "fuel0": s.tanks * TANK_FUEL,
			"boosters": nb, "b_dry": nb * BOOSTER.dry, "b_fuel": nb * BOOSTER.fuel, "b_fuel0": nb * BOOSTER.fuel,
			"fins": s.get("fins", false), "h": e.h + s.tanks * TANK_H + DEC_H})
	return out

static func design_stats(d: Dictionary) -> Dictionary:
	var st := stage_data(d)
	var total := 0.0
	for i in st.size():
		var above := CAPSULE_MASS
		for j in range(i + 1, st.size()):
			above += st[j].dry + st[j].fuel
		var s: Dictionary = st[i]
		var m: float = above + s.dry + s.fuel + s.b_dry + s.b_fuel
		var fuel: float = s.fuel
		if s.boosters > 0:
			var md_b: float = s.boosters * BOOSTER.thrust / (BOOSTER.isp_vac * P.G0)
			var md_c: float = s.e.thrust / (s.e.isp_vac * P.G0)
			var t_b: float = s.b_fuel / md_b
			var use_c: float = min(fuel, md_c * t_b)
			var veff: float = (s.boosters * BOOSTER.thrust + s.e.thrust) / (md_b + md_c) * 0.97
			var m1: float = m - s.b_fuel - use_c
			total += veff * log(m / m1)
			fuel -= use_c
			m = m1 - s.b_dry
		total += s.e.isp_vac * P.G0 * log(m / (m - fuel)) * (0.96 if i == 0 else 1.0)
	var mass := CAPSULE_MASS
	var height := CAPSULE_H
	for s in st:
		mass += s.dry + s.fuel + s.b_dry + s.b_fuel
		height += s.h
	var s0: Dictionary = st[0]
	var th: float = s0.e.thrust * s0.e.isp_sl / s0.e.isp_vac + s0.boosters * BOOSTER.thrust * BOOSTER.isp_sl / BOOSTER.isp_vac
	return {"dv": total, "twr": th / (mass * P.G0), "mass": mass, "height": height}

# ---------- Shader für Flamme und Plasma ----------
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float power = 1.0;
uniform float vac = 0.0;
uniform vec3 hot = vec3(1.0, 0.97, 0.6);
uniform vec3 mid = vec3(1.0, 0.62, 0.08);
uniform vec3 tail = vec3(1.0, 0.25, 0.08);
uniform float diamonds = 1.0;
varying float t;
varying vec3 lp;
float h3(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vn(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z); }
void vertex(){ t = clamp(0.5 - VERTEX.y, 0.0, 1.0); lp = VERTEX; }
void fragment(){
	float edge = abs(dot(NORMAL, VIEW));
	vec3 q = vec3(lp.x * 3.0, lp.y * 6.0 + TIME * 9.0, lp.z * 3.0);
	float n = vn(q) * 0.6 + vn(q * 2.3 + 7.0) * 0.4;
	float fl = 0.75 + 0.45 * n;
	vec3 c = mix(hot, mid, smoothstep(0.0, 0.42, t));
	c = mix(c, tail, smoothstep(0.42, 1.0, t));
	c = mix(c, vec3(0.55, 0.7, 1.0), vac * 0.5 * smoothstep(0.05, 0.7, t));
	float sd = pow(max(0.0, sin(t * 38.0 - 1.2)), 10.0) * (1.0 - smoothstep(0.0, 0.55, t)) * (1.0 - vac) * diamonds;
	float core = smoothstep(0.35, 0.0, t) * pow(edge, 3.0);
	float a = pow(1.0 - t, 1.25) * pow(edge, 1.1 + vac) * fl * power * (1.0 - vac * 0.45);
	ALBEDO = c * (1.5 + core * 1.5) + vec3(1.0, 0.95, 0.7) * sd * 2.0;
	ALPHA = clamp(a * 1.6, 0.0, 0.95);
}
"""
static var _flame_shader: Shader
static func flame_material(power := 1.0) -> ShaderMaterial:
	if _flame_shader == null:
		_flame_shader = Shader.new(); _flame_shader.code = FLAME_SHADER
	var mm := ShaderMaterial.new(); mm.shader = _flame_shader
	mm.set_shader_parameter("power", power)
	return mm

## Flamme: Kegel mit Spitze nach unten, Ursprung an der Düse. Länge über scale.y.
static func make_flame(r: float) -> Node3D:
	var root := Node3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 0.02; cm.height = 1.0; cm.radial_segments = 28; cm.rings = 6; cm.cap_top = false; cm.cap_bottom = false
	var fmat := flame_material()
	for k in 2:
		var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = fmat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = -0.5
		if k == 1:
			mi.scale = Vector3(0.55, 0.7, 0.55); mi.position.y = -0.35
		root.add_child(mi)
	root.set_meta("r", r)
	root.set_meta("mat", fmat)
	root.visible = false
	return root

static func make_plasma() -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 0.05; cm.height = 1.0; cm.radial_segments = 32; cm.rings = 6; cm.cap_top = false; cm.cap_bottom = false
	var pm := flame_material(0.0)
	pm.set_shader_parameter("hot", Vector3(1.0, 0.95, 0.8))
	pm.set_shader_parameter("mid", Vector3(1.0, 0.45, 0.1))
	pm.set_shader_parameter("tail", Vector3(1.0, 0.25, 0.35))
	pm.set_shader_parameter("diamonds", 0.0)
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

# ---------- 3D-Teile ----------
const Gfx := preload("res://scripts/gfx.gd")
static var _mats := {}
static func m(name: String) -> Material:
	if _mats.is_empty():
		var T := preload("res://scripts/toon.gd")
		_mats.white = T.plastic(Color(0.97, 0.97, 0.99), 0.32, 0.7)
		_mats.dark = T.plastic(Color(0.22, 0.24, 0.3), 0.4, 0.5)
		_mats.metal = T.plastic(Color(0.72, 0.76, 0.84), 0.3, 0.6)
		_mats.copper = T.plastic(Color(1.0, 0.55, 0.15), 0.3, 0.7)
		_mats.gold = T.plastic(Color(1.0, 0.78, 0.2), 0.3, 0.7)
		_mats.shield = T.plastic(Color(0.45, 0.3, 0.2), 0.6, 0.2)
		_mats.glass = T.plastic(Color(0.3, 0.75, 1.0), 0.05, 1.0)
		_mats.chute = T.plastic(Color(1.0, 0.45, 0.1), 0.5, 0.3).duplicate()
		_mats.chute2 = T.plastic(Color(1, 1, 1), 0.5, 0.3).duplicate()
		_mats.black = T.plastic(Color(0.12, 0.12, 0.15), 0.4, 0.4)
		for k in ["chute", "chute2"]:
			_mats[k].cull_mode = BaseMaterial3D.CULL_DISABLED
		for i in STAGE_COLORS.size():
			_mats["c%d" % i] = T.plastic(STAGE_COLORS[i].lightened(0.05), 0.3, 0.8)
	return _mats[name]

static func _bell_mat() -> StandardMaterial3D:
	# eigene Kopie pro Düse, damit sie beim Feuern glühen kann
	var b: StandardMaterial3D = m("dark").duplicate()
	b.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.emission_enabled = true; b.emission = Color(1.0, 0.35, 0.08); b.emission_energy_multiplier = 0.0
	return b

static var _font: FontVariation
static func _label(text: String, size: float, col: Color) -> Label3D:
	if _font == null:
		_font = FontVariation.new(); _font.base_font = load("res://fonts/Baloo2.ttf")
		_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	var l := Label3D.new()
	l.text = text; l.font = _font; l.font_size = 96; l.pixel_size = size / 96.0; l.modulate = col
	l.outline_size = 0; l.double_sided = false; l.shaded = true
	return l

## Blender-Modell laden (models/*.glb)
static var _scenes := {}
static func model(name: String) -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load("res://models/%s.glb" % name)
	return (_scenes[name] as PackedScene).instantiate()

## Material mit bestimmtem Namen in allen Teilen ersetzen
static func tint(node: Node, mat_name: String, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mm := mi.mesh.surface_get_material(i)
			if mm and mm.resource_name == mat_name:
				mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		tint(c, mat_name, mat)

static func build_capsule() -> Node3D:
	var g := Node3D.new()
	g.add_child(model("capsule"))
	# Fallschirm (eingeklappt)
	var chute := Node3D.new(); chute.name = "Chute"
	var canopy := MeshInstance3D.new(); var sm := SphereMesh.new()
	sm.radius = 9.0; sm.height = 7.0; sm.is_hemisphere = true; sm.radial_segments = 32; sm.rings = 10
	canopy.mesh = sm; canopy.material_override = m("chute"); canopy.position.y = 26.0; chute.add_child(canopy)
	for k in 6:
		var stripe := MeshInstance3D.new(); var ss := SphereMesh.new()
		ss.radius = 9.03; ss.height = 7.0; ss.is_hemisphere = true; ss.radial_segments = 32; ss.rings = 10
		stripe.mesh = ss; stripe.material_override = m("chute2"); stripe.position.y = 26.0; stripe.scale = Vector3(0.12, 1.0, 1.0)
		stripe.rotation.y = k * PI / 6.0; chute.add_child(stripe)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in 12:
		var a := float(k) / 12.0 * TAU
		im.surface_add_vertex(Vector3(0, 2.8, 0)); im.surface_add_vertex(Vector3(cos(a) * 8.6, 26.0, sin(a) * 8.6))
	im.surface_end()
	var lines := MeshInstance3D.new(); lines.mesh = im; lines.material_override = W.mat(Color(0.9, 0.9, 0.9), 1.0, 0.0)
	chute.add_child(lines)
	chute.visible = false; chute.scale = Vector3.ONE * 0.01
	g.add_child(chute)
	g.set_meta("chute", chute)
	return g

static func build_stage(s: Dictionary, color_idx: int, idx: int) -> Node3D:
	var g := Node3D.new()
	var e: Dictionary = ENGINES[s.engine]
	var stripe := m("c%d" % ((color_idx + idx) % STAGE_COLORS.size()))
	var top: float = e.h + s.tanks * TANK_H
	# Halterung und Düse (Blender-Modelle)
	var mount := model("mount"); mount.position.y = e.h - 0.6; g.add_child(mount)
	var bell_mat := _bell_mat()
	var bell := model("bell"); bell.scale = Vector3(e.bell, e.h - 0.5, e.bell); g.add_child(bell)
	tint(bell, "Dark", bell_mat)
	var flame := make_flame(e.bell); flame.name = "Flame"; g.add_child(flame)
	g.set_meta("flame", flame)
	g.set_meta("bell_mat", bell_mat)
	var body_col: StandardMaterial3D = preload("res://scripts/toon.gd").plastic(STAGE_COLORS[(color_idx + idx) % STAGE_COLORS.size()].lerp(Color.WHITE, 0.25), 0.3, 0.8)
	for i in s.tanks:
		var t := model("tank"); t.position.y = e.h + i * TANK_H; g.add_child(t)
		if i % 2 == 1:
			tint(t, "White", body_col)
			tint(t, "Paint", m("white"))
		else:
			tint(t, "Paint", stripe)
	var name_l := _label("PAUL" if idx == 0 else "PAUL %d" % (idx + 1), 0.62, Color(0.1, 0.12, 0.2))
	name_l.rotation = Vector3(0, 0, PI / 2.0)
	name_l.position = Vector3(0, e.h + s.tanks * TANK_H * 0.55, RC + 0.035)
	g.add_child(name_l)
	var dec := model("decoupler"); dec.position.y = top; g.add_child(dec)
	if s.get("fins", false):
		for k in 4:
			var a := (k + 0.5) / 4.0 * TAU
			var holder := Node3D.new(); holder.rotation.y = -a
			var fin := model("fin"); fin.position = Vector3(RC * 0.92, e.h + 0.1, 0)
			tint(fin, "Paint", stripe)
			holder.add_child(fin); g.add_child(holder)
	var nb: int = s.get("boosters", 0)
	if nb > 0:
		var boosters := Node3D.new(); boosters.name = "Boosters"
		var flames := []
		for k in nb:
			var a := float(k) / nb * TAU
			var bg := Node3D.new()
			var bm := model("booster"); bg.add_child(bm)
			tint(bm, "Paint", stripe)
			tint(bm, "Dark", _bell_mat())
			for yy in [2.2, 8.0]:
				var strut := W.box(Vector3(0.12, 0.12, 0.45), m("metal")); strut.rotation.y = -a
				strut.position = Vector3(-cos(a), 0, -sin(a)) * (BOOSTER.r + 0.05) + Vector3(0, yy, 0); bg.add_child(strut)
			var fl := make_flame(BOOSTER.r * 0.78); bg.add_child(fl); flames.append(fl)
			bg.position = Vector3(cos(a) * (RC + BOOSTER.r + 0.05), e.h * 0.3, sin(a) * (RC + BOOSTER.r + 0.05))
			boosters.add_child(bg)
		boosters.set_meta("flames", flames)
		g.add_child(boosters)
		g.set_meta("boosters", boosters)
	g.set_meta("h", e.h + s.tanks * TANK_H + DEC_H)
	return g

## Ganze Rakete für die Werft, Unterkante bei y=0
static func build_rocket(d: Dictionary) -> Node3D:
	var g := Node3D.new()
	var y := 0.0
	var stages := []
	for i in d.stages.size():
		var sg := build_stage(d.stages[i], d.get("color", 0), i)
		sg.position.y = y; y += sg.get_meta("h"); g.add_child(sg); stages.append(sg)
	var cap := build_capsule(); cap.position.y = y; g.add_child(cap)
	y += CAPSULE_H
	g.set_meta("stages", stages)
	g.set_meta("h", y)
	return g
