extends SceneTree
## Rechnet durch, bei welchem Startwinkel und welchem Schub (Delta-v) die Bahn
## um den Mond herum zur Erde zurückführt (freie Rückkehr).
## Start: Godot --headless --path . -s tools/moon_scan.gd
const P := preload("res://scripts/phys.gd")

func _init() -> void:
	var r := P.R + P.ORBIT_ALT
	var vc := sqrt(P.GM / r)
	var t0 := 0.0
	var ma0 := P.moon_angle(t0)
	var hits := 0
	for lead_deg in range(96, 121, 2):
		var line := "lead %3d: " % lead_deg
		for dv in range(200, 291, 3):
			var phi := ma0 - deg_to_rad(lead_deg)
			var x := r * cos(phi); var y := r * sin(phi)
			var sp := vc + dv
			var vx := -sin(phi) * sp; var vy := cos(phi) * sp
			var p := P.predict(x, y, vx, vy, t0, 1.0, 2800.0, {"long": true, "stop_atm": true, "max_t": 14000.0})
			var ch := "."
			if p.get("back", false):
				ch = "B"; hits += 1
				if p.moon_min - P.RMOON < 60000.0 and lead_deg in [100, 104, 108]:
					print("  B lead %d dv %d  Mondabstand %d km(Spiel) roh %d" % [lead_deg, dv, int((p.moon_min - P.RMOON) * P.ALT_K / 1000.0), int(p.moon_min - P.RMOON)])
			elif p.has("moon_hit"):
				ch = "x"
			elif p.has("impact"):
				ch = "i"
			elif p.get("away", false):
				ch = "a"
			elif p.moon_min - P.RMOON < 40000.0:
				ch = "n"
			line += ch
		print(line)
	print("dv-Spalten 200..290 in 3er-Schritten, B = zurück zur Erde, x = Mond getroffen, a = weggeflogen, n = nah am Mond, . = kein Mond")
	print("treffer ", hits, "  MOON_LEAD im Spiel: ", rad_to_deg(108.0 * PI / 180.0))
	quit()
