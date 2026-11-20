extends Node3D
## Die Welt: Erde, Bodenstück, Wolken, Atmosphäre, Sternenhimmel, Sonne, Mond, Startplatz, Bergungsschiff.
## Physik-Ebene = x/y-Ebene, Erdmittelpunkt im Ursprung, z zeigt aus der Bahnebene heraus.

const P := preload("res://scripts/phys.gd")

var planet: MeshInstance3D
var patch: MeshInstance3D
var clouds: MeshInstance3D
var atmosphere: MeshInstance3D
var moon: MeshInstance3D
var pad: Node3D
var pad_arm: Node3D
var ship: Node3D
var sun_light: DirectionalLight3D
var env: Environment
var mats := {}
var _time := 0.0

const NOISE := """
vec3 mod289_3(vec3 x){ return x - floor(x * (1.0/289.0)) * 289.0; }
vec4 mod289_4(vec4 x){ return x - floor(x * (1.0/289.0)) * 289.0; }
vec4 permute4(vec4 x){ return mod289_4(((x*34.0)+1.0)*x); }
vec4 tis4(vec4 r){ return 1.79284291400159 - 0.85373472095314 * r; }
float snoise(vec3 v){
	vec2 C = vec2(1.0/6.0, 1.0/3.0);
	vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;
	i = mod289_3(i);
	vec4 p = permute4(permute4(permute4(i.z + vec4(0.0, i1.z, i2.z, 1.0)) + i.y + vec4(0.0, i1.y, i2.y, 1.0)) + i.x + vec4(0.0, i1.x, i2.x, 1.0));
	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);
	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	vec4 norm = tis4(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
	p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}
"""

func _planet_shader() -> String:
	return """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 sun_dir;
uniform vec3 sky_col;
uniform float haze;
uniform float time;
varying vec3 wpos;
""" + NOISE + P.land_glsl() + """
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 p = normalize(wpos);
	float f = landF(p);
	vec3 V = cam - wpos; float dist = length(V); V /= dist;
	float lat = asin(clamp(p.z, -1.0, 1.0));
	float d1 = snoise(p * 70.0), d2 = snoise(p * 420.0);
	float d3 = dist < 25000.0 ? snoise(p * 3200.0) * smoothstep(25000.0, 3000.0, dist) : 0.0;
	vec3 col; float ocean = 0.0; float city = 0.0; vec3 n = p;
	if (f < 0.0) {
		ocean = 1.0; float shl = smoothstep(-0.32, 0.0, f);
		col = mix(vec3(0.01, 0.06, 0.20), vec3(0.03, 0.30, 0.50), shl * shl);
		if (dist < 25000.0) { vec3 q = wpos * 0.035 + vec3(time * 0.35); float k = 0.05 * smoothstep(25000.0, 1500.0, dist);
			n = normalize(p + k * vec3(snoise(q), snoise(q + 11.3), snoise(q + 27.1))); }
		col += vec3(0.0, 0.02, 0.03) * smoothstep(0.0, 1.0, snoise(p * 40.0) * 0.5 + 0.5);
	} else {
		float beach = smoothstep(0.03, 0.0, f);
		float hum = snoise(p * 3.0 + 5.0) * 0.5 + 0.5;
		float desert = smoothstep(0.55, 0.8, hum) * (1.0 - smoothstep(0.35, 0.6, abs(lat)));
		vec3 grass = mix(vec3(0.22, 0.50, 0.18), vec3(0.10, 0.31, 0.12), smoothstep(-0.3, 0.5, d1));
		col = mix(grass, vec3(0.80, 0.67, 0.42), desert);
		col = mix(col, vec3(0.46, 0.41, 0.37), smoothstep(0.75, 1.15, f + d1 * 0.15));
		float snow = smoothstep(1.1, 1.3, f + d1 * 0.1);
		col = mix(col, vec3(0.93, 0.95, 1.0), snow);
		col = mix(col, vec3(0.88, 0.82, 0.62), beach);
		col *= 0.92 + 0.08 * d2 + 0.06 * d3;
		// Felder und Wälder aus der Nähe
		if (dist < 18000.0) {
			float fade = smoothstep(18000.0, 4000.0, dist) * (1.0 - desert) * (1.0 - beach);
			float fld = snoise(p * 2600.0 + 3.0);
			vec3 fieldc = mix(vec3(0.55, 0.52, 0.22), vec3(0.32, 0.5, 0.16), step(0.0, snoise(p * 900.0 - 2.0)));
			col = mix(col, fieldc, smoothstep(0.35, 0.45, fld) * 0.3 * fade);
			col = mix(col, vec3(0.1, 0.32, 0.12), smoothstep(0.1, 0.3, -fld) * 0.25 * fade);
		}
		// Relief: Hänge werden je nach Sonne heller oder dunkler
		if (dist < 40000.0) {
			float e = 0.00012;
			float hh = snoise(p * 380.0) + 0.5 * snoise(p * 1500.0);
			vec3 tx = normalize(cross(p, vec3(0.0, 0.0, 1.0)));
			vec3 ty = cross(p, tx);
			float hx = snoise((p + tx * e) * 380.0) + 0.5 * snoise((p + tx * e) * 1500.0);
			float hy = snoise((p + ty * e) * 380.0) + 0.5 * snoise((p + ty * e) * 1500.0);
			float relief = (0.15 + smoothstep(0.5, 1.1, f)) * smoothstep(40000.0, 2000.0, dist);
			n = normalize(p - (tx * (hx - hh) + ty * (hy - hh)) * relief * 2.5);
		}
		float region = smoothstep(0.25, 0.6, snoise(p * 14.0 + 7.0));
		float dots = smoothstep(0.55, 0.85, snoise(p * 700.0)) + 0.6 * smoothstep(0.7, 0.95, snoise(p * 2200.0));
		city = region * dots * (1.0 - snow) * (1.0 - desert * 0.7) * smoothstep(0.02, 0.12, f);
	}
	float polar = smoothstep(0.90, 0.95, abs(p.z) + snoise(p * 8.0) * 0.03);
	col = mix(col, vec3(0.9, 0.94, 1.0), polar); ocean *= 1.0 - polar;
	float ndl = dot(n, sun_dir), ndlp = dot(p, sun_dir);
	float day = smoothstep(-0.12, 0.22, ndlp);
	vec3 lit = col * (0.025 + 1.2 * max(ndl, 0.0));
	lit *= mix(vec3(1.0, 0.72, 0.5), vec3(1.0), smoothstep(0.0, 0.35, ndlp));
	vec3 Hh = normalize(sun_dir + V);
	lit += vec3(1.0, 0.93, 0.8) * pow(max(dot(n, Hh), 0.0), 140.0) * ocean * 1.4 * day;
	lit += vec3(1.0, 0.72, 0.35) * city * (1.0 - day) * 0.8;
	// Himmel spiegelt sich im Meer
	float fres = pow(1.0 - max(dot(n, V), 0.0), 5.0);
	lit += sky_col * fres * ocean * 0.6;
	// Wolkenschatten
	vec3 cq = p * 5.0 + vec3(time * 0.0015, time * 0.0008, 0.0);
	float cl = snoise(cq) * 0.6 + snoise(cq * 2.3) * 0.3 + snoise(cq * 6.0) * 0.16;
	lit *= 1.0 - 0.42 * smoothstep(0.12, 0.62, cl) * day;
	float rim = pow(1.0 - max(dot(p, V), 0.0), 3.0) * smoothstep(3000.0, 20000.0, length(cam) - %f);
	lit += vec3(0.25, 0.5, 1.0) * rim * 0.55 * smoothstep(-0.2, 0.3, ndlp);
	lit = mix(lit, sky_col, (1.0 - exp(-dist / 9000.0)) * haze);
	ALBEDO = lit;
}
""" % P.R

func _cloud_shader() -> String:
	return """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec3 sun_dir;
uniform float time;
varying vec3 wpos;
""" + NOISE + """
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 p = normalize(wpos);
	vec3 q = p * 5.0 + vec3(time * 0.0015, time * 0.0008, 0.0);
	float c = snoise(q) * 0.6 + snoise(q * 2.3) * 0.3 + snoise(q * 6.0) * 0.16 + snoise(p * 34.0) * 0.09 + snoise(p * 160.0) * 0.05;
	float a = smoothstep(0.12, 0.62, c);
	a *= smoothstep(0.012, 0.05, distance(p, vec3(0.0, 1.0, 0.0)));
	float ndl = dot(p, sun_dir); float day = smoothstep(-0.15, 0.25, ndl);
	vec3 col = vec3(1.0) * (0.03 + 0.97 * day) * mix(vec3(1.0, 0.68, 0.48), vec3(1.0), smoothstep(0.0, 0.3, ndl));
	a *= smoothstep(120.0, 1400.0, length(cam - wpos));
	ALBEDO = col;
	ALPHA = a * 0.88;
}
"""

func _atm_shader() -> String:
	return """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add;
uniform vec3 sun_dir;
varying vec3 wpos;
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 rd = normalize(wpos - cam);
	float tca = -dot(cam, rd);
	vec3 cp = cam + rd * max(tca, 0.0);
	float h = length(cp) - %f;
	float dens = exp(-max(h, 0.0) / 2300.0);
	float s = dot(normalize(cp), sun_dir);
	float light_amt = smoothstep(-0.28, 0.22, s);
	vec3 c = mix(vec3(1.0, 0.42, 0.18), vec3(0.30, 0.56, 1.0), smoothstep(-0.05, 0.35, s));
	float glow = pow(max(dot(rd, sun_dir), 0.0), 10.0);
	ALBEDO = (c * 1.15 + vec3(1.0, 0.8, 0.55) * glow * 0.7) * dens * light_amt;
	ALPHA = 1.0;
}
""" % P.R

func _moon_shader() -> String:
	return """
shader_type spatial;
render_mode unshaded;
uniform vec3 sun_dir;
varying vec3 lpos;
""" + NOISE + """
void vertex(){ lpos = VERTEX; }
void fragment(){
	vec3 p = normalize(lpos);
	float n = snoise(p * 3.0) * 0.5 + snoise(p * 9.0) * 0.25 + snoise(p * 30.0) * 0.12 + snoise(p * 120.0) * 0.06;
	float maria = smoothstep(0.05, 0.35, snoise(p * 1.4 + 3.0));
	vec3 col = mix(vec3(0.66, 0.65, 0.63), vec3(0.36, 0.36, 0.37), maria) * (0.85 + 0.3 * n);
	float cr = 1.0 - abs(snoise(p * 16.0)); float cr2 = 1.0 - abs(snoise(p * 55.0));
	col *= 0.9 + 0.14 * pow(cr, 8.0) + 0.08 * pow(cr2, 10.0);
	ALBEDO = col * (0.015 + 1.15 * max(dot(p, sun_dir), 0.0));
}
"""

const SKY_SHADER := """
shader_type sky;
uniform vec3 sun_dir;
uniform float stars_vis = 1.0;
float hash(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void sky(){
	vec3 d = EYEDIR;
	vec3 g = floor(d * 380.0);
	float h = hash(g);
	float star = step(0.9965, h) * (0.4 + 0.6 * hash(g + 3.1));
	vec3 col = vec3(star) * stars_vis * mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), hash(g + 7.7));
	float sd = max(dot(d, sun_dir), 0.0);
	col += vec3(1.0, 0.95, 0.85) * (pow(sd, 2200.0) * 40.0 + pow(sd, 120.0) * 0.6 + pow(sd, 12.0) * 0.08);
	COLOR = col;
}
"""

func _ready() -> void:
	var sun := P.sun_dir()
	# Umgebung: Sternenhimmel, Tonemapping, Leuchten
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	var sky_sh := Shader.new(); sky_sh.code = SKY_SHADER
	sky_mat.shader = sky_sh
	sky_mat.set_shader_parameter("sun_dir", sun)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.78)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for lv in range(7):
		env.set_glow_level(lv, lv in [2, 3, 4])
	env.ssao_enabled = true
	env.ssao_radius = 2.0; env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06; env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	mats.sky = sky_mat

	sun_light = DirectionalLight3D.new()
	sun_light.light_energy = 2.2
	sun_light.light_color = Color(1.0, 0.96, 0.9)
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 700.0
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.shadow_blur = 1.5
	sun_light.light_angular_distance = 0.5
	add_child(sun_light)
	sun_light.look_at_from_position(Vector3.ZERO, -sun, Vector3.FORWARD if abs(sun.y) > 0.99 else Vector3.UP)

	# Erde
	mats.planet = _shader_mat(_planet_shader())
	var sm := SphereMesh.new(); sm.radius = P.R - 1.5; sm.height = 2.0 * (P.R - 1.5); sm.radial_segments = 512; sm.rings = 256
	planet = MeshInstance3D.new(); planet.mesh = sm; planet.material_override = mats.planet
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(planet)
	# Feines Bodenstück (die große Kugel ist aus der Nähe zu eckig)
	patch = MeshInstance3D.new(); patch.mesh = _patch_mesh(); patch.material_override = mats.planet
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)
	# Wolken
	mats.clouds = _shader_mat(_cloud_shader())
	var cm := SphereMesh.new(); cm.radius = P.R + 2300.0; cm.height = 2.0 * (P.R + 2300.0); cm.radial_segments = 256; cm.rings = 128
	clouds = MeshInstance3D.new(); clouds.mesh = cm; clouds.material_override = mats.clouds
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)
	# Atmosphäre
	mats.atm = _shader_mat(_atm_shader())
	var am := SphereMesh.new(); am.radius = P.R + 9500.0; am.height = 2.0 * (P.R + 9500.0); am.radial_segments = 192; am.rings = 96
	atmosphere = MeshInstance3D.new(); atmosphere.mesh = am; atmosphere.material_override = mats.atm
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmosphere)
	# Mond
	mats.moon = _shader_mat(_moon_shader())
	var mm := SphereMesh.new(); mm.radius = P.RMOON; mm.height = 2.0 * P.RMOON; mm.radial_segments = 128; mm.rings = 64
	moon = MeshInstance3D.new(); moon.mesh = mm; moon.material_override = mats.moon
	add_child(moon)
	for k in ["planet", "clouds", "atm", "moon"]:
		mats[k].set_shader_parameter("sun_dir", sun)
	_build_pad()
	_build_ship()
	_build_scenery()

func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new(); sh.code = code
	var m := ShaderMaterial.new(); m.shader = sh
	return m

func _patch_mesh() -> ArrayMesh:
	var rings := 90
	var segs := 160
	var radius := 9000.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in range(1, rings + 1):
		var a := pow(float(i) / rings, 2.2) * radius / P.R
		for j in segs:
			var b := float(j) / segs * TAU
			verts.append(Vector3(sin(a) * cos(b) * P.R, cos(a) * P.R - P.R, sin(a) * sin(b) * P.R))
	var idx := PackedInt32Array()
	for j in segs:
		idx.append_array(PackedInt32Array([0, 1 + j, 1 + (j + 1) % segs]))
	for i in range(1, rings):
		for j in segs:
			var a := 1 + (i - 1) * segs + j
			var b := 1 + (i - 1) * segs + (j + 1) % segs
			var c := 1 + i * segs + j
			var d := 1 + i * segs + (j + 1) % segs
			idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

static func mat(c: Color, rough := 0.5, metal := 0.15, emission := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if emission != Color.BLACK:
		m.emission_enabled = true; m.emission = emission
	return m

static func box(size: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = m
	return mi

static func cyl(top: float, bottom: float, h: float, m: Material, seg := 40) -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = top; cm.bottom_radius = bottom; cm.height = h; cm.radial_segments = seg; cm.rings = 1
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = m
	return mi

func _build_pad() -> void:
	var Gfx := preload("res://scripts/gfx.gd")
	pad = Node3D.new()
	var ct := Gfx.concrete_textures()
	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = ct[0]; concrete.normal_enabled = true; concrete.normal_texture = ct[1]; concrete.roughness = 0.92
	concrete.uv1_triplanar = true; concrete.uv1_scale = Vector3(0.05, 0.05, 0.05)
	var T := preload("res://scripts/toon.gd")
	var tower := T.plastic(Color(0.95, 0.3, 0.25), 0.35, 0.6)
	var steel := T.plastic(Color(0.8, 0.84, 0.9), 0.35, 0.6)
	concrete.albedo_color = Color(0.86, 0.9, 0.98); concrete.roughness = 0.55
	# Betonplatte und Sockel
	var apron := cyl(140.0, 140.0, 2.0, concrete, 96); apron.position.y = -0.95; pad.add_child(apron)
	var base := box(Vector3(46, 14, 46), concrete); base.position.y = -7.0 + 0.02; pad.add_child(base)
	var trench := box(Vector3(7, 1.2, 34), T.plastic(Color(0.3, 0.34, 0.45), 0.5, 0.3)); trench.position.y = 0.0; pad.add_child(trench)
	var mark := T.torus(22.0, 23.2, T.plastic(Color(1.0, 0.8, 0.2), 0.35, 0.6)); mark.scale = Vector3(1, 0.04, 1); mark.position.y = 0.05; pad.add_child(mark)
	var mark2 := T.torus(60.0, 61.5, T.plastic(Color(0.3, 0.6, 1.0), 0.35, 0.6)); mark2.scale = Vector3(1, 0.04, 1); mark2.position.y = 0.05; pad.add_child(mark2)
	# Startturm als Gitter
	for xz in [[-11, -5], [-11, 5], [-19, -5], [-19, 5]]:
		var c := box(Vector3(1.0, 56, 1.0), tower); c.position = Vector3(xz[0], 28, xz[1]); pad.add_child(c)
	for y in range(3, 56, 3):
		for z in [-5, 5]:
			var b := box(Vector3(9, 0.35, 0.35), tower); b.position = Vector3(-15, y, z); pad.add_child(b)
			var dg := box(Vector3(0.25, 4.2, 0.25), tower); dg.position = Vector3(-15, y + 1.5, z); dg.rotation.z = 1.1 if (y / 3) % 2 == 0 else -1.1; pad.add_child(dg)
		for x in [-11, -19]:
			var b2 := box(Vector3(0.35, 0.35, 10), tower); b2.position = Vector3(x, y, 0); pad.add_child(b2)
			var dg2 := box(Vector3(0.25, 4.2, 0.25), tower); dg2.position = Vector3(x, y + 1.5, 0); dg2.rotation.x = 1.1 if (y / 3) % 2 == 0 else -1.1; pad.add_child(dg2)
	var roof := box(Vector3(10, 0.6, 12), steel); roof.position = Vector3(-15, 56.3, 0); pad.add_child(roof)
	for k in 3:
		var arm2 := box(Vector3(6, 0.5, 0.8), steel); arm2.position = Vector3(-8, 8 + k * 9, 0); pad.add_child(arm2)
	pad_arm = Node3D.new(); pad_arm.position = Vector3(-10.5, 30, 0); pad.add_child(pad_arm)
	var arm := box(Vector3(8, 1.2, 2.0), steel); arm.position.x = 4.0; pad_arm.add_child(arm)
	var lamp := MeshInstance3D.new(); var ls := SphereMesh.new(); ls.radius = 0.6; ls.height = 1.2; lamp.mesh = ls
	lamp.material_override = mat(Color(1, 0.2, 0.2), 0.5, 0.0, Color(4, 0.3, 0.3)); lamp.position = Vector3(-15, 57.2, 0); pad.add_child(lamp)
	# Blitzableiter-Masten
	for xz in [[30, 30], [-34, 28], [28, -32], [-30, -30]]:
		var mast := cyl(0.35, 0.6, 70, steel, 10); mast.position = Vector3(xz[0], 35, xz[1]); pad.add_child(mast)
	# Scheinwerfermasten, auf die Rakete gerichtet
	for xz in [[55, 40], [-50, 45], [45, -55]]:
		var mast2 := box(Vector3(0.8, 26, 0.8), steel); mast2.position = Vector3(xz[0], 13, xz[1]); pad.add_child(mast2)
		var head := box(Vector3(5, 2.5, 1), mat(Color(0.2, 0.2, 0.22), 0.5, 0.3, Color(3.0, 2.8, 2.4))); head.position = Vector3(xz[0], 26.5, xz[1]); pad.add_child(head)
		var sp := SpotLight3D.new(); sp.light_energy = 6.0; sp.spot_range = 180.0; sp.spot_angle = 14.0; sp.light_color = Color(1.0, 0.95, 0.85)
		pad.add_child(sp); sp.position = Vector3(xz[0], 26.0, xz[1])
		sp.set_meta("local_target", Vector3(0, 14, 0))
	# Wasserturm und Treibstofftanks
	var wt := MeshInstance3D.new(); var wsm := SphereMesh.new(); wsm.radius = 7.0; wsm.height = 14.0; wt.mesh = wsm; wt.material_override = T.plastic(Color(0.35, 0.6, 1.0), 0.3, 0.7)
	wt.position = Vector3(-60, 34, -40); pad.add_child(wt)
	var wl := cyl(1.2, 1.5, 28, steel, 12); wl.position = Vector3(-60, 14, -40); pad.add_child(wl)
	for k in 2:
		var ft := MeshInstance3D.new(); var fs := SphereMesh.new(); fs.radius = 6.0; fs.height = 12.0; ft.mesh = fs; ft.material_override = T.plastic(Color(1.0, 0.8, 0.25), 0.3, 0.7)
		ft.position = Vector3(65 + k * 16, 6, -25); pad.add_child(ft)
	var bunker := box(Vector3(14, 6, 10), T.plastic(Color(0.4, 0.8, 0.55), 0.35, 0.6)); bunker.position = Vector3(70, 3, 40); pad.add_child(bunker)
	pad.position = Vector3(0, P.R, 0)
	add_child(pad)
	for c in pad.get_children():
		if c is SpotLight3D:
			c.look_at(pad.to_global(c.get_meta("local_target")), Vector3.UP)

## Spielzeugbäume, Häuschen und Wattewolken rund um den Startplatz
func _build_scenery() -> void:
	var Parts := preload("res://scripts/parts.gd")
	var rng := RandomNumberGenerator.new(); rng.seed = 42
	var scen := Node3D.new(); scen.name = "Scenery"; add_child(scen)
	var place := func(e: float, n: float, h: float) -> Transform3D:
		var dir := (Vector3(0, P.R, 0) + Vector3(1, 0, 0) * e + Vector3(0, 0, 1) * n).normalized()
		var up := dir
		var fw := Vector3(0, 0, 1).slide(up).normalized()
		return Transform3D(Basis(fw.cross(up), up, fw).orthonormalized(), dir * (P.R + h))
	var count := 0
	var tries := 0
	while count < 220 and tries < 3000:
		tries += 1
		var dist := rng.randf_range(170.0, 2600.0)
		var ang := rng.randf() * TAU
		var e := cos(ang) * dist
		var n := sin(ang) * dist
		var tr: Transform3D = place.call(e, n, -0.3)
		var d := tr.origin.normalized()
		if P.land_field(d.x, d.y, d.z) < 0.03:
			continue
		if absf(e) < 140.0 and absf(n) < 140.0:
			continue
		var kind := "pine" if rng.randf() < 0.45 else ("house" if rng.randf() < 0.12 else "tree")
		var obj := Parts.model(kind)
		obj.transform = tr * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(2.2, 4.0)), Vector3.ZERO)
		scen.add_child(obj)
		count += 1
	# dicke Wattewolken in der unteren Luft, auch entlang der Flugbahn nach Osten
	for k in 46:
		var e := rng.randf_range(-3500.0, 6000.0)
		var n := rng.randf_range(-3500.0, 3500.0)
		if absf(e) < 250.0 and absf(n) < 250.0:
			continue
		var c := Parts.model("cloud")
		c.transform = place.call(-e, n, rng.randf_range(700.0, 2600.0)) * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.6, 1.0) * rng.randf_range(45.0, 140.0)), Vector3.ZERO)
		scen.add_child(c)

func _build_ship() -> void:
	ship = Node3D.new()
	var white := mat(Color(0.95, 0.96, 0.98))
	var hull := box(Vector3(10, 3, 34), white); hull.position.y = 1.0; ship.add_child(hull)
	var deck := box(Vector3(8, 5, 10), mat(Color(0.18, 0.43, 0.88))); deck.position = Vector3(0, 5, -6); ship.add_child(deck)
	var crane := box(Vector3(0.8, 10, 0.8), mat(Color(0.78, 0.25, 0.18))); crane.position = Vector3(0, 7, 6); ship.add_child(crane)
	ship.visible = false
	add_child(ship)

func place_ship_near(x: float, y: float) -> void:
	var r := sqrt(x * x + y * y)
	var u := Vector3(x / r, y / r, 0)
	var e := Vector3(-u.y, u.x, 0)
	ship.global_transform = Transform3D(Basis(e, u, Vector3(0, 0, 1)), u * P.R + e * 70.0 + Vector3(0, 0, 25))
	ship.visible = true

## Pro Bild: Uniforms, Himmel, Bodenstück, Licht im Erdschatten
func update_world(dt: float, cam: Camera3D, sim_t: float, focus: Vector3) -> void:
	_time += dt
	var sun := P.sun_dir()
	var cp := cam.global_position
	var calt := cp.length() - P.R
	var up := cp.normalized()
	var sd := up.dot(sun)
	var day := smoothstep(-0.22, 0.25, sd)
	var dens := exp(-max(0.0, calt) / 2300.0)
	var sunset := 1.0 - smoothstep(-0.05, 0.35, sd)
	var sky := Color(lerp(0.36, 0.9, sunset) * day + 0.01, lerp(0.58, 0.45, sunset) * day + 0.015, lerp(1.0, 0.35, sunset) * day + 0.03)
	mats.planet.set_shader_parameter("sky_col", Vector3(sky.r, sky.g, sky.b))
	mats.planet.set_shader_parameter("haze", clamp(dens * 0.45, 0.0, 0.45))
	mats.planet.set_shader_parameter("time", _time)
	mats.clouds.set_shader_parameter("time", _time)
	mats.sky.set_shader_parameter("stars_vis", clamp(1.0 - day * dens * 1.7, 0.04, 1.0))
	var ma := P.moon_angle(sim_t)
	moon.position = Vector3(P.RM * cos(ma), P.RM * sin(ma), 0)
	# Erdschatten
	var along := focus.dot(sun)
	var perp := sqrt(max(0.0, focus.length_squared() - along * along))
	var lit := 1.0 if (along > 0.0 or perp > P.R) else smoothstep(P.R - 400.0, P.R + 400.0, perp)
	sun_light.light_energy = 2.2 * lit
	env.ambient_light_energy = 0.25 + 0.35 * day * dens + 0.45 * (1.0 - lit)
	# Bodenstück unter die Kamera legen
	if calt < 18000.0:
		patch.visible = true
		var u := Vector3(cp.x, cp.y, 0).normalized()
		patch.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, u)), u * P.R)
	else:
		patch.visible = false
	pad.visible = Vector2(cp.x, cp.y - P.R).length() < 40000.0
	var sc := get_node_or_null("Scenery")
	if sc:
		sc.visible = Vector2(cp.x, cp.y - P.R).length() < 60000.0
