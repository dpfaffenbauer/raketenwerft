extends RefCounted
## Eine Rakete im Flug: Stufen, Treibstoff, Schub, Abwerfen, 3D-Modell.

const P := preload("res://scripts/phys.gd")
const Parts := preload("res://scripts/parts.gd")

var design: Dictionary
var st: Array
var s := 0                 # unterste noch vorhandene Stufe
var boost := false
var x := 0.0
var y := P.R
var vx := 0.0
var vy := 0.0
var hd := PI / 2.0         # Blickrichtung in der Bahnebene
var throttle := 0.0
var chute := false
var chute_open := 0.0
var landed := true
var on_pad := false
var splashed := false
var heat := 0.0
var q := 0.0
var g_load := 0.0
var g_max := 0.0
var thrust_n := 0.0
var h := 0.0
var mass_ := 1.0
var cd_a_ := 1.0

var group: Node3D          # Mittelpunkt der Rakete
var stack: Node3D
var stage_nodes: Array = []
var cap: Node3D
var plasma: MeshInstance3D
var smoke: CPUParticles3D

func _init(d: Dictionary, parent: Node3D) -> void:
	design = d.duplicate(true)
	st = Parts.stage_data(design)
	boost = st.size() > 0 and st[0].boosters > 0
	group = Node3D.new(); stack = Node3D.new(); group.add_child(stack); parent.add_child(group)
	var yy := 0.0
	for i in design.stages.size():
		var sg := Parts.build_stage(design.stages[i], design.get("color", 0), i)
		sg.position.y = yy; yy += sg.get_meta("h"); stack.add_child(sg); stage_nodes.append(sg)
	cap = Parts.build_capsule(); cap.position.y = yy; stack.add_child(cap)
	plasma = Parts.make_plasma(); group.add_child(plasma)
	relayout()

func capsule_only() -> bool:
	return s >= st.size()

func height() -> float:
	var hh := Parts.CAPSULE_H
	for i in range(s, st.size()):
		hh += st[i].h
	return hh

func relayout() -> void:
	h = height()
	var y0 := 0.0
	for i in s:
		y0 += st[i].h
	stack.position.y = -y0 - h / 2.0

func mass() -> float:
	var mm := Parts.CAPSULE_MASS
	for i in range(s, st.size()):
		mm += st[i].dry + st[i].fuel
	if boost:
		mm += st[0].b_dry + st[0].b_fuel
	return mm * 1000.0

func cd_a() -> float:
	if chute_open > 0.0:
		return 6.0 + chute_open * 110.0
	if capsule_only():
		return 1.3 * PI * Parts.RC * Parts.RC
	return 0.4 * PI * Parts.RC * Parts.RC * (1.5 if boost else 1.0)

func dir() -> Vector2:
	return Vector2(cos(hd), sin(hd))

func stage_empty() -> bool:
	return capsule_only() or st[s].fuel <= 0.0

func all_empty() -> bool:
	for i in range(s, st.size()):
		if st[i].fuel > 0.0:
			return false
	return true

## Schub in Newton bei Luftdruck p (0..1); verbraucht Treibstoff über dt
func thrust(p: float, dt: float) -> float:
	if throttle <= 0.0 or capsule_only():
		return 0.0
	var F := 0.0
	var sd: Dictionary = st[s]
	if sd.fuel > 0.0:
		var e: Dictionary = sd.e
		var mdot: float = e.thrust * 1000.0 / (e.isp_vac * P.G0) * throttle
		var isp: float = e.isp_vac + (e.isp_sl - e.isp_vac) * p
		F += mdot * isp * P.G0
		sd.fuel = max(0.0, sd.fuel - mdot * dt / 1000.0)
	if boost and s == 0 and sd.b_fuel > 0.0:
		var B := Parts.BOOSTER
		var mdb: float = sd.boosters * B.thrust * 1000.0 / (B.isp_vac * P.G0)
		var ispb: float = B.isp_vac + (B.isp_sl - B.isp_vac) * p
		F += mdb * ispb * P.G0
		sd.b_fuel = max(0.0, sd.b_fuel - mdb * dt / 1000.0)
	return F

## Restliche Reichweite (Delta-v in m/s) mit dem Treibstoff, der noch da ist
func dv_left() -> float:
	var dv := 0.0
	for i in range(s, st.size()):
		var above := Parts.CAPSULE_MASS
		for j in range(i + 1, st.size()):
			above += st[j].dry + st[j].fuel
		var sd: Dictionary = st[i]
		dv += sd.e.isp_vac * P.G0 * log((above + sd.dry + sd.fuel) / (above + sd.dry))
	return dv

func firing() -> bool:
	if throttle <= 0.0 or capsule_only():
		return false
	return st[s].fuel > 0.0 or (boost and st[0].b_fuel > 0.0)
