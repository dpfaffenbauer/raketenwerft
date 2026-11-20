extends RefCounted
## Spielzeug-Look (Vinyl-Figuren): glänzendes Plastik, runde Formen, Figuren mit großem Kopf.

static var _mats := {}

## Glänzendes Plastik in einer Farbe
static func plastic(c: Color, rough := 0.38, coat := 0.6) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), rough, coat]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = 0.0
	m.clearcoat_enabled = coat > 0.0; m.clearcoat = coat; m.clearcoat_roughness = 0.25
	m.rim_enabled = true; m.rim = 0.25; m.rim_tint = 0.6
	_mats[key] = m
	return m

static func sphere(r: float, m: Material, seg := 32) -> MeshInstance3D:
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = seg; sm.rings = seg / 2
	var mi := MeshInstance3D.new(); mi.mesh = sm; mi.material_override = m
	return mi

static func capsule(r: float, h: float, m: Material) -> MeshInstance3D:
	var cm := CapsuleMesh.new(); cm.radius = r; cm.height = maxf(h, r * 2.0); cm.radial_segments = 24; cm.rings = 8
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = m
	return mi

static func torus(inner: float, outer: float, m: Material) -> MeshInstance3D:
	var tm := TorusMesh.new(); tm.inner_radius = inner; tm.outer_radius = outer; tm.rings = 32; tm.ring_segments = 12
	var mi := MeshInstance3D.new(); mi.mesh = tm; mi.material_override = m
	return mi

## Astronaut Paul (Blender-Modell, ca. 2,2 hoch, Füße bei y=0)
static func astronaut() -> Node3D:
	var g := Node3D.new()
	var p: Node3D = (load("res://models/paul.glb") as PackedScene).instantiate()
	p.scale = Vector3.ONE * 0.78
	g.add_child(p)
	var bubble := p.find_child("Bubble", true, false) as MeshInstance3D
	if bubble:   # Glashelm: kein Schatten aufs Gesicht, glänzend wie Plexiglas
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gm := StandardMaterial3D.new()
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color = Color(0.82, 0.93, 1.0, 0.12)
		gm.roughness = 0.03; gm.metallic_specular = 1.0
		gm.rim_enabled = true; gm.rim = 0.6; gm.rim_tint = 0.2
		gm.clearcoat_enabled = true; gm.clearcoat = 1.0; gm.clearcoat_roughness = 0.02
		bubble.material_override = gm
	g.set_meta("head", p.find_child("Head", true, false))
	g.set_meta("arm_r", p.find_child("ArmR", true, false))
	g.set_meta("arm_l", p.find_child("ArmL", true, false))
	return g

## Sanfte Animation (winken / wippen)
static func animate(g: Node3D, t: float, wave := true) -> void:
	var head: Node3D = g.get_meta("head")
	if head:
		head.rotation.z = sin(t * 1.3) * 0.06
		head.rotation.x = sin(t * 0.9) * 0.04
	var ar: Node3D = g.get_meta("arm_r")
	if ar:
		ar.rotation.z = (2.6 + sin(t * 7.0) * 0.35) if wave else (0.25 + sin(t * 1.5) * 0.05)
	var al: Node3D = g.get_meta("arm_l")
	if al:
		al.rotation.z = -0.25 - sin(t * 1.5) * 0.05

## Hintergrund wie ein Fotostudio: großer Verlauf von hellblau nach blau
static func studio_backdrop() -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_front;
varying vec3 lp;
void vertex(){ lp = VERTEX; }
void fragment(){
	float t = clamp(normalize(lp).y * 0.9 + 0.35, 0.0, 1.0);
	vec3 top = vec3(0.42, 0.72, 0.95);
	vec3 bot = vec3(0.22, 0.38, 0.85);
	ALBEDO = mix(bot, top, t);
}
"""
	var m := ShaderMaterial.new(); m.shader = sh
	var s := sphere(400.0, m, 48)
	return s
