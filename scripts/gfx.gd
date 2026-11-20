extends RefCounted
## Grafik-Bausteine: per Code erzeugte Texturen (Bleche, Nieten, Beton, Rauch),
## gedrehte Formen (Düsen, Nasen, Kapsel) und ausgestanzte Flächen (Flossen).

static var _cache := {}

static func _noise(seed: int, freq: float, octaves := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed; n.frequency = freq; n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n

## Tank-Haut: weiße Bleche mit Schweißnähten, Nieten und leichten Gebrauchsspuren.
## Gibt [albedo, normal, roughness] zurück. UV: u = rundherum, v = Länge.
static func tank_textures() -> Array:
	if _cache.has("tank"):
		return _cache.tank
	var s := 512
	var alb := Image.create(s, s, false, Image.FORMAT_RGB8)
	var hgt := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rough := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(3, 0.012, 5)
	var n2 := _noise(9, 0.08, 2)
	for y in s:
		for x in s:
			var u := float(x) / s
			var v := float(y) / s
			var seam_v := absf(fposmod(u * 8.0, 1.0) - 0.5) > 0.493
			var seam_h := absf(fposmod(v * 2.0, 1.0) - 0.5) > 0.49
			var rivet := false
			if absf(fposmod(v * 2.0, 1.0) - 0.5) > 0.465 and absf(fposmod(v * 2.0, 1.0) - 0.5) < 0.485:
				rivet = fposmod(u * 96.0, 1.0) < 0.35
			var grime := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := 0.93 - grime * 0.06 + n2.get_noise_2d(x, y) * 0.015
			var h := 0.5
			if seam_v or seam_h:
				c -= 0.12; h = 0.3
			if rivet:
				c -= 0.05; h = 0.75
			alb.set_pixel(x, y, Color(c, c * 1.005, c * 1.02))
			hgt.set_pixel(x, y, Color(h, h, h))
			var r := 0.38 + grime * 0.25 + (0.15 if seam_v or seam_h else 0.0)
			rough.set_pixel(x, y, Color(r, r, r))
	alb.generate_mipmaps(); rough.generate_mipmaps()
	hgt.bump_map_to_normal_map(3.0)
	hgt.generate_mipmaps()
	var out := [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(hgt), ImageTexture.create_from_image(rough)]
	_cache.tank = out
	return out

## Gebürstetes Metall für Düsen (dunkel, mit Längsrillen).
static func metal_textures() -> Array:
	if _cache.has("metal"):
		return _cache.metal
	var s := 256
	var hgt := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(21, 0.3, 2)
	for y in s:
		for x in s:
			var ridge := 0.5 + 0.25 * sin(float(x) / s * TAU * 64.0) + n.get_noise_2d(x * 4, y * 0.2) * 0.15
			hgt.set_pixel(x, y, Color(ridge, ridge, ridge))
	hgt.bump_map_to_normal_map(1.5)
	hgt.generate_mipmaps()
	var out := [ImageTexture.create_from_image(hgt)]
	_cache.metal = out
	return out

## Beton mit Fugen und Flecken
static func concrete_textures() -> Array:
	if _cache.has("concrete"):
		return _cache.concrete
	var s := 512
	var alb := Image.create(s, s, false, Image.FORMAT_RGB8)
	var hgt := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := _noise(5, 0.01, 5)
	var n2 := _noise(6, 0.2, 2)
	for y in s:
		for x in s:
			var joint := (x % 128 < 3) or (y % 128 < 3)
			var c := 0.58 + n.get_noise_2d(x, y) * 0.12 + n2.get_noise_2d(x, y) * 0.04
			if joint:
				c *= 0.6
			alb.set_pixel(x, y, Color(c, c * 0.98, c * 0.94))
			var h := 0.3 if joint else 0.5 + n2.get_noise_2d(x, y) * 0.1
			hgt.set_pixel(x, y, Color(h, h, h))
	alb.generate_mipmaps()
	hgt.bump_map_to_normal_map(2.0); hgt.generate_mipmaps()
	var out := [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(hgt)]
	_cache.concrete = out
	return out

## Weiche, wolkige Rauchflocke
static func puff_texture() -> Texture2D:
	if _cache.has("puff"):
		return _cache.puff
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := _noise(11, 0.045, 4)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var nn := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 - 0.25 + (nn - 0.5) * 0.9, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var shade := 0.82 + nn * 0.18
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache.puff = t
	return t

## Drehkörper aus Profil [(radius, höhe), …] von unten nach oben
static func lathe(profile: Array, mat: Material, seg := 48, smooth := true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if smooth:
		st.set_smooth_group(0)
	else:
		st.set_smooth_group(-1)
	var n := profile.size()
	for i in n - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for j in seg:
			var a0 := float(j) / seg * TAU
			var a1 := float(j + 1) / seg * TAU
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var u0 := float(j) / seg
			var u1 := float(j + 1) / seg
			var t0 := float(i) / (n - 1)
			var t1 := float(i + 1) / (n - 1)
			st.set_uv(Vector2(u0, 1.0 - t0)); st.add_vertex(v00)
			st.set_uv(Vector2(u1, 1.0 - t1)); st.add_vertex(v11)
			st.set_uv(Vector2(u0, 1.0 - t1)); st.add_vertex(v10)
			st.set_uv(Vector2(u0, 1.0 - t0)); st.add_vertex(v00)
			st.set_uv(Vector2(u1, 1.0 - t0)); st.add_vertex(v01)
			st.set_uv(Vector2(u1, 1.0 - t1)); st.add_vertex(v11)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

## Fläche aus Umriss (in x/y) mit Dicke in z – für Flossen
static func extrude(poly: PackedVector2Array, depth: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(poly)
	var hz := depth / 2.0
	for k in range(0, tri.size(), 3):
		var a := poly[tri[k]]; var b := poly[tri[k + 1]]; var c := poly[tri[k + 2]]
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(a.x, a.y, hz)); st.add_vertex(Vector3(b.x, b.y, hz)); st.add_vertex(Vector3(c.x, c.y, hz))
		st.set_normal(Vector3(0, 0, -1))
		st.add_vertex(Vector3(a.x, a.y, -hz)); st.add_vertex(Vector3(c.x, c.y, -hz)); st.add_vertex(Vector3(b.x, b.y, -hz))
	for i in poly.size():
		var p := poly[i]; var q := poly[(i + 1) % poly.size()]
		var e := (q - p).normalized()
		var nrm := Vector3(e.y, -e.x, 0)
		st.set_normal(nrm)
		st.add_vertex(Vector3(p.x, p.y, hz)); st.add_vertex(Vector3(q.x, q.y, -hz)); st.add_vertex(Vector3(q.x, q.y, hz))
		st.add_vertex(Vector3(p.x, p.y, hz)); st.add_vertex(Vector3(p.x, p.y, -hz)); st.add_vertex(Vector3(q.x, q.y, -hz))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

## Glockenförmige Düse (Profil wie echte Raketendüse)
static func bell_profile(r_throat: float, r_exit: float, h: float) -> Array:
	var pts := []
	for i in 13:
		var t := float(i) / 12.0
		var r := r_throat + (r_exit - r_throat) * (1.0 - pow(1.0 - t, 2.2))
		pts.append(Vector2(r, h * (1.0 - t)))
	pts.reverse()
	return pts
