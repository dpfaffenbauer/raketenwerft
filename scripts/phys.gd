extends RefCounted
## Physik der Raketenwerft: ein kleiner Planet (Radius 60 km), damit alles schnell geht.
## Die Anzeige rechnet in „echte“ Zahlen um (Orbit in 15 km = 400 km, 686 m/s = 27.600 km/h).
## Gleiche Formeln wie in raketenwerft.html (dort mit Node getestet).

const Lang := preload("res://scripts/lang.gd")

const R := 60000.0
const G0 := 9.81
const GM := G0 * R * R
const ATM := 4500.0
const HS := 800.0
const RHO0 := 1.2
const ORBIT_ALT := 15000.0
const ALT_K := 400.0 / 15.0
const SPD_K := 7660.0 / 686.2 * 3.6
const SPACE_ALT := 100.0 / ALT_K * 1000.0
const RM := 600000.0
const GMM := GM * 0.0123
const RMOON := 15000.0
static var WM: float = sqrt(GM / pow(RM, 3.0))
static var moon_theta0: float = 1.2

const SUN := Vector3(0.5, 0.74, -0.45)

static func sun_dir() -> Vector3:
	return SUN.normalized()

static func rho(h: float) -> float:
	if h >= ATM:
		return 0.0
	return RHO0 * exp(-h / HS) * (1.0 - h / ATM)

static func moon_angle(t: float) -> float:
	return moon_theta0 + WM * t

static func moon_xy(t: float) -> Vector2:
	var a := moon_angle(t)
	return Vector2(RM * cos(a), RM * sin(a))  # nur für Anzeige; Physik nutzt Floats

static func ang_diff(a: float, b: float) -> float:
	var d := fmod(a - b, TAU)
	if d > PI:
		d -= TAU
	if d < -PI:
		d += TAU
	return d

static func fmt_km(m: float) -> String:
	return _thousands(int(round(max(0.0, m) / 1000.0 * ALT_K)))

static func fmt_kmh(v: float) -> String:
	return _thousands(int(round(v * SPD_K / 100.0) * 100.0))

static func _thousands(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = Lang.thousands_sep() + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

# ---------- Rauschen (Ashima simplex, identisch zur Shader-Version) ----------
static func _m289(x: float) -> float:
	return x - floorf(x / 289.0) * 289.0

static func _perm(x: float) -> float:
	return _m289((x * 34.0 + 1.0) * x)

static func snoise(vx: float, vy: float, vz: float) -> float:
	var s := (vx + vy + vz) / 3.0
	var ix := floorf(vx + s)
	var iy := floorf(vy + s)
	var iz := floorf(vz + s)
	var t := (ix + iy + iz) / 6.0
	var x0 := vx - ix + t
	var y0 := vy - iy + t
	var z0 := vz - iz + t
	var gx := 1.0 if x0 >= y0 else 0.0
	var gy := 1.0 if y0 >= z0 else 0.0
	var gz := 1.0 if z0 >= x0 else 0.0
	var lx := 1.0 - gx
	var ly := 1.0 - gy
	var lz := 1.0 - gz
	var i1x: float = min(gx, lz)
	var i1y: float = min(gy, lx)
	var i1z: float = min(gz, ly)
	var i2x: float = max(gx, lz)
	var i2y: float = max(gy, lx)
	var i2z: float = max(gz, ly)
	var X := [
		[x0, y0, z0],
		[x0 - i1x + 1.0 / 6.0, y0 - i1y + 1.0 / 6.0, z0 - i1z + 1.0 / 6.0],
		[x0 - i2x + 1.0 / 3.0, y0 - i2y + 1.0 / 3.0, z0 - i2z + 1.0 / 3.0],
		[x0 - 0.5, y0 - 0.5, z0 - 0.5]]
	ix = _m289(ix); iy = _m289(iy); iz = _m289(iz)
	var oz := [0.0, i1z, i2z, 1.0]
	var oy := [0.0, i1y, i2y, 1.0]
	var ox := [0.0, i1x, i2x, 1.0]
	var sum := 0.0
	var nsx := 2.0 / 7.0
	var nsy := 0.5 / 7.0 - 1.0
	var nsz := 1.0 / 7.0
	for k in 4:
		var p := _perm(_perm(_perm(iz + oz[k]) + iy + oy[k]) + ix + ox[k])
		var j := p - 49.0 * floorf(p * nsz * nsz)
		var x_ := floorf(j * nsz)
		var y_ := floorf(j - 7.0 * x_)
		var a := x_ * nsx + nsy
		var b := y_ * nsx + nsy
		var h := 1.0 - absf(a) - absf(b)
		var sh := -1.0 if h <= 0.0 else 0.0
		a += (floorf(a) * 2.0 + 1.0) * sh
		b += (floorf(b) * 2.0 + 1.0) * sh
		var nrm := 1.79284291400159 - 0.85373472095314 * (a * a + b * b + h * h)
		var q: Array = X[k]
		var m: float = max(0.6 - (q[0] * q[0] + q[1] * q[1] + q[2] * q[2]), 0.0)
		m *= m
		sum += m * m * nrm * (a * q[0] + b * q[1] + h * q[2])
	return 42.0 * sum

# Kontinente: [Winkel°, Breite°, Größe, Gewicht] – negativ = Ozean erzwingen
const BLOBS := [[90.0, 6.0, 0.40, 1.35], [195.0, 12.0, 0.42, 1.2], [242.0, -42.0, 0.45, 1.15], [28.0, -12.0, 0.30, 1.1],
	[142.0, 56.0, 0.40, 1.1], [330.0, 48.0, 0.28, 0.9], [300.0, 0.0, 0.55, -1.4], [128.0, 0.0, 0.17, -0.9], [60.0, -60.0, 0.25, 0.8]]
const LAND_BASE := -0.46

static func land_field(px: float, py: float, pz: float) -> float:
	var f := LAND_BASE
	for bl in BLOBS:
		var ph: float = deg_to_rad(bl[0])
		var la: float = deg_to_rad(bl[1])
		var r: float = bl[2]
		var cx := cos(la) * cos(ph)
		var cy := cos(la) * sin(ph)
		var cz := sin(la)
		f += bl[3] * exp(-2.0 * (1.0 - (px * cx + py * cy + pz * cz)) / (r * r))
	return f + 0.42 * snoise(px * 1.8, py * 1.8, pz * 1.8) + 0.22 * snoise(px * 4.0, py * 4.0, pz * 4.0) \
		+ 0.1 * snoise(px * 9.0, py * 9.0, pz * 9.0) + 0.05 * snoise(px * 20.0, py * 20.0, pz * 20.0)

static var _rim_cache: PackedByteArray = PackedByteArray()

static func is_land_at(phi: float) -> bool:
	if _rim_cache.is_empty():
		_rim_cache.resize(1440)
		for i in 1440:
			var a := float(i) / 1440.0 * TAU
			_rim_cache[i] = 1 if land_field(cos(a), sin(a), 0.0) > 0.0 else 0
	var idx := int(round(fposmod(phi, TAU) / TAU * 1440.0)) % 1440
	return _rim_cache[idx] == 1

static func land_glsl() -> String:
	# Erzeugt dieselbe Landfunktion als Shader-Code
	var s := "float landF(vec3 p){\n\tfloat f = %f;\n" % LAND_BASE
	for bl in BLOBS:
		var ph: float = deg_to_rad(bl[0])
		var la: float = deg_to_rad(bl[1])
		var r: float = bl[2]
		s += "\tf += %f * exp(-2.0 * (1.0 - dot(p, vec3(%f, %f, %f))) / %f);\n" % [bl[3], cos(la) * cos(ph), cos(la) * sin(ph), sin(la), r * r]
	s += "\treturn f + 0.42*snoise(p*1.8) + 0.22*snoise(p*4.0) + 0.1*snoise(p*9.0) + 0.05*snoise(p*20.0);\n}\n"
	return s

# ---------- Bahnelemente ----------
static func elements(x: float, y: float, vx: float, vy: float) -> Dictionary:
	var r := sqrt(x * x + y * y)
	var v2 := vx * vx + vy * vy
	var E := v2 / 2.0 - GM / r
	var h := x * vy - y * vx
	if E >= 0.0:
		return {"esc": true, "ap": INF, "pe": INF, "r": r}
	var a := -GM / (2.0 * E)
	var e := sqrt(max(0.0, 1.0 + 2.0 * E * h * h / (GM * GM)))
	var rv := x * vx + y * vy
	var ex := ((v2 - GM / r) * x - rv * vx) / GM
	var ey := ((v2 - GM / r) * y - rv * vy) / GM
	var pe_a := atan2(ey, ex)
	return {"esc": false, "a": a, "e": e, "ap": a * (1.0 + e) - R, "pe": a * (1.0 - e) - R,
		"T": TAU * sqrt(pow(a, 3.0) / GM), "pe_a": pe_a, "ap_a": pe_a + PI, "r": r}

static func time_to_apo(x: float, y: float, vx: float, vy: float) -> float:
	var el := elements(x, y, vx, vy)
	if el.esc:
		return INF
	if x * vx + y * vy <= 0.0:
		return 0.0
	var t := 0.0
	var h := 0.5
	while t < el.T:
		var r := sqrt(x * x + y * y)
		var g := GM / (r * r * r)
		vx -= x * g * h; vy -= y * g * h
		x += vx * h; y += vy * h
		t += h
		if x * vx + y * vy <= 0.0:
			return t
	return t

# Beschleunigung durch Erde + Mond. Gibt [ax, ay, Abstand zum Mond] zurück.
static func grav(x: float, y: float, t: float) -> Array:
	var r2 := x * x + y * y
	var r := sqrt(r2)
	var g := GM / (r2 * r)
	var ax := -x * g
	var ay := -y * g
	var ma := moon_angle(t)
	var dx := x - RM * cos(ma)
	var dy := y - RM * sin(ma)
	var d2 := dx * dx + dy * dy
	var d := sqrt(d2)
	var gm := GMM / (d2 * d)
	return [ax - dx * gm, ay - dy * gm, d]

# Vorausschau der Flugbahn (ohne Schub, mit Luftwiderstand)
static func predict(x: float, y: float, vx: float, vy: float, t: float, cd_a: float, mass: float, opts := {}) -> Dictionary:
	var max_t: float = opts.get("max_t", 20000.0)
	var long_flight: bool = opts.get("long", false)
	var stop_atm: bool = opts.get("stop_atm", false)
	var pts := PackedVector2Array()
	pts.append(Vector2(x, y))
	var T := 0.0
	var swept := 0.0
	var last_a := atan2(y, x)
	var moon_min := INF
	var moon_min_t := 0.0
	var left_earth := false
	var max_r := 0.0
	var res := {}
	while T < max_t:
		var r := sqrt(x * x + y * y)
		var alt := r - R
		var ma := moon_angle(t)
		var dm := sqrt(pow(x - RM * cos(ma), 2.0) + pow(y - RM * sin(ma), 2.0))
		var h: float = min(sqrt(pow(r, 3.0) / GM), sqrt(pow(dm, 3.0) / GMM)) * 0.006
		h = min(h, 0.6) if alt < ATM + 300.0 else clamp(h, 0.3, 40.0)
		var a := grav(x, y, t)
		var ax: float = a[0]
		var ay: float = a[1]
		if alt < ATM and cd_a > 0.0:
			var sp := sqrt(vx * vx + vy * vy)
			var k := 0.5 * rho(alt) * sp * cd_a / mass
			ax -= k * vx; ay -= k * vy
		vx += ax * h; vy += ay * h
		x += vx * h; y += vy * h
		t += h; T += h
		var an := atan2(y, x)
		swept += ang_diff(an, last_a); last_a = an
		if dm < moon_min:
			moon_min = dm; moon_min_t = T
		max_r = max(max_r, r)
		if r > 150000.0:
			left_earth = true
		if pts.size() < 4000:
			pts.append(Vector2(x, y))
		var rn := sqrt(x * x + y * y)
		if rn <= R:
			pts.append(Vector2(x, y))
			res.impact = {"x": x, "y": y, "phi": atan2(y, x), "t": T, "land": is_land_at(atan2(y, x))}
			break
		if dm < RMOON:
			res.moon_hit = true
			break
		if rn > RM * 1.7:
			res.away = true
			break
		if left_earth and stop_atm and rn < R + ATM + 600.0:
			res.back = true
			break
		if not left_earth and not long_flight and abs(swept) > TAU + 0.03:
			res.full = true
			break
	res.pts = pts
	res.moon_min = moon_min
	res.moon_min_t = moon_min_t
	res.left_earth = left_earth
	res.max_r = max_r
	return res
