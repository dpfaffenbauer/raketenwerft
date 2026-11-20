extends CanvasLayer
## Oberfläche: Titel, Werft-Baukasten, Cockpit-Anzeigen, Karte, Richtungsanzeige, Mira, Touch-Knöpfe.

const P := preload("res://scripts/phys.gd")
const Parts := preload("res://scripts/parts.gd")
const Missions := preload("res://scripts/missions.gd")
const L := preload("res://scripts/lines.gd")
const T := preload("res://scripts/lang.gd")

const INK := Color(0.11, 0.16, 0.27)
const CARD := Color(1.0, 0.97, 0.93)
const EDGE := Color(0.85, 0.76, 0.63)
const SUN := Color(1.0, 0.82, 0.25)
const GO := Color(0.24, 0.86, 0.52)

var main
var font: Font
var theme_main: Theme

var title_box: Control
var cards_grid: GridContainer
var hangar_box: Control
var rows_box: VBoxContainer
var stats_box: VBoxContainer
var hud_box: Control
var m_title: Label
var m_obj: Label
var tele: Label
var stages_lbl: Label
var keys_lbl: Label
var warp_lbl: Label
var big_lbl: Label
var navball: Control
var map: Control
var caption: PanelContainer
var cap_text: Label
var touch: Control
var result_box: Control
var pause_box: Control
var facts_box: Control
var r_icon: Label
var r_title: Label
var r_facts: Label
var r_next: Button
var r_again: Button
var map_big := false
var sci_on := false
var _big_t := 0.0
var _static: Array = []   # [Knoten, deutscher Text] – feste Texte, die beim Sprachwechsel neu gesetzt werden

func _ready() -> void:
	layer = 10
	var base := load("res://fonts/Baloo2.ttf") as FontFile
	# Emojis: mitgelieferte Noto-Emoji (nur die Zeichen, die das Spiel braucht; OFL-Lizenz).
	# Apples Emoji-Schrift ist auf neuen iOS-Versionen komprimiert und für Godot unlesbar.
	var emoji := load("res://fonts/NotoColorEmoji-sub.ttf") as FontFile
	base.fallbacks = [emoji]
	var fv := FontVariation.new(); fv.base_font = base; fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	font = fv
	theme_main = Theme.new()
	theme_main.default_font = font
	theme_main.default_font_size = 22
	_build_title()
	_build_hangar()
	_build_hud()
	_build_caption()
	_build_result()
	_build_pause()
	_build_facts()
	show_only("")

# ---------- Hilfen ----------
func _style(bg: Color, radius := 22, shadow := Color(0, 0, 0, 0), border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 10; s.content_margin_bottom = 10
	if shadow.a > 0.0:
		s.shadow_color = shadow; s.shadow_size = 0; s.shadow_offset = Vector2(0, 6)
		s.expand_margin_bottom = 0
	if border.a > 0.0:
		s.set_border_width_all(4); s.border_color = border
	return s

func _glass() -> StyleBoxFlat:
	return _style(Color(0.04, 0.06, 0.13, 0.74), 18)

func _label(text: String, size := 22, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _button(text: String, cb: Callable, yellow := true, size := 24) -> Button:
	var b := Button.new(); b.text = text
	b.add_theme_font_size_override("font_size", size)
	var bg := SUN if yellow else CARD
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _style(bg, 18, Color(0.79, 0.6, 0.06) if yellow else EDGE))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.15), 18))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK)
	b.pressed.connect(_on_button.bind(cb))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # Wischen auf dem Knopf scrollt die Liste dahinter
	return b

## Festen Text merken und gleich in der eingestellten Sprache anzeigen.
func _reg(n: Control):
	var de: String = n.text
	_static.append([n, de])
	n.text = T.t(de)
	return n

## Sprache gewechselt: alle festen Texte, Titelkarten und Knöpfe neu beschriften.
func retranslate() -> void:
	for e in _static:
		if is_instance_valid(e[0]):
			e[0].text = T.t(e[1])
	build_cards(main.progress.done, main.title_sel)
	if touch:
		touch.queue_redraw()

func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)

func show_only(name: String) -> void:
	title_box.visible = name == "title"
	hangar_box.visible = name == "hangar"
	hud_box.visible = name == "flight"
	touch.visible = name == "flight" and DisplayServer.is_touchscreen_available()
	_place_caption(name)
	result_box.visible = name == "result"
	pause_box.visible = false
	facts_box.visible = name == "facts"
	if name != "flight" and name != "hangar" and name != "result":
		caption.visible = false

# =====================================================================
#  Titel
# =====================================================================
func _build_title() -> void:
	title_box = Control.new(); _full(title_box); title_box.theme = theme_main; add_child(title_box)
	var shade := ColorRect.new(); _full(shade); shade.color = Color(0.02, 0.03, 0.09, 0.35); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; title_box.add_child(shade)
	var scroll := ScrollContainer.new(); _full(scroll); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; title_box.add_child(scroll)
	var margin := MarginContainer.new(); margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); margin.add_child(v)
	var t: Label = _reg(_label("Pauls Raketenwerft", 64, SUN)); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6)); t.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(t)
	var sub: Label = _reg(_label("Bau deine Rakete, flieg in den Orbit, besuch die ISS – und bring sie sicher nach Hause!", 22))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(sub)
	cards_grid = GridContainer.new(); cards_grid.columns = 4
	cards_grid.add_theme_constant_override("h_separation", 16); cards_grid.add_theme_constant_override("v_separation", 16)
	cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(cards_grid)
	var bar := HBoxContainer.new(); bar.alignment = BoxContainer.ALIGNMENT_CENTER; bar.add_theme_constant_override("separation", 14)
	bar.add_child(_button("🔊 Ton", _toggle_sound, false))
	bar.add_child(_reg(_button("📒 Wissen", func(): main.show_facts(), false)))
	var lang_btn := _button("", toggle_lang, false)
	bar.add_child(lang_btn)
	v.add_child(bar)
	title_box.set_meta("sound_btn", bar.get_child(0))
	title_box.set_meta("lang_btn", lang_btn)
	get_viewport().size_changed.connect(_relayout)

func _update_sound_btn() -> void:
	var b: Button = title_box.get_meta("sound_btn")
	b.text = T.t("🔊 Ton an" if main.audio.on else "🔇 Ton aus")
	# Sprachknopf zeigt die eingestellte Sprache, Tippen wechselt
	(title_box.get_meta("lang_btn") as Button).text = "🌍 Deutsch" if T.current() == "de" else "🌍 English"

## Sprache umschalten (Titel-Knopf oder Taste L): Texte sofort neu, Mira spricht ab jetzt in der neuen Sprache.
func toggle_lang() -> void:
	T.toggle()
	retranslate()
	main.audio.stop_voice()
	main.say("welcome")

func build_cards(done: Dictionary, sel: int) -> void:
	for c in cards_grid.get_children():
		c.queue_free()
	for i in Missions.LIST.size():
		var m: Dictionary = Missions.LIST[i]
		var b := Button.new()
		b.text = "%s   %d%s\n%s\n%s" % [m.icon, i + 1, "  ⭐" if done.get(m.id, false) else "", T.t(m.title), T.t(m.sub)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(250, 170)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		var border := SUN if i == sel else Color(0, 0, 0, 0)
		for st in ["normal", "hover", "focus"]:
			b.add_theme_stylebox_override(st, _style(CARD, 22, EDGE, border))
		b.add_theme_stylebox_override("pressed", _style(CARD.darkened(0.08), 22, EDGE, border))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, INK)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		var idx := i
		b.pressed.connect(_on_card.bind(idx))
		cards_grid.add_child(b)
	_update_sound_btn()
	_relayout()

func _relayout() -> void:
	var w := get_viewport().get_visible_rect().size.x
	cards_grid.columns = 4 if w > 1100 else (3 if w > 800 else 2)
	if map:
		_place_map()

# =====================================================================
#  Werft
# =====================================================================
func _build_hangar() -> void:
	hangar_box = Control.new(); _full(hangar_box); hangar_box.theme = theme_main; hangar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hangar_box)
	var left := PanelContainer.new(); left.add_theme_stylebox_override("panel", _glass())
	left.anchor_top = 0; left.anchor_bottom = 1; left.offset_left = 14; left.offset_top = 14; left.offset_bottom = -96; left.offset_right = 400
	hangar_box.add_child(left)
	var lv := VBoxContainer.new(); lv.add_theme_constant_override("separation", 6); left.add_child(lv)
	lv.add_child(_reg(_label("🔧 Baukasten", 30)))
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	rows_box = VBoxContainer.new(); rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows_box.add_theme_constant_override("separation", 6); sc.add_child(rows_box)
	var pre := HFlowContainer.new(); pre.add_theme_constant_override("h_separation", 8); pre.add_theme_constant_override("v_separation", 8)
	for pk in [["Hüpfer", "hop"], ["Orbit-Rakete", "orbit"], ["Mond-Rakete", "moon"]]:
		var key: String = pk[1]
		pre.add_child(_reg(_button(pk[0], func(): main.hangar_preset(key), false, 17)))
	lv.add_child(pre)
	var right := PanelContainer.new(); right.add_theme_stylebox_override("panel", _glass())
	right.anchor_left = 1; right.anchor_right = 1; right.offset_left = -360; right.offset_right = -14; right.offset_top = 14
	hangar_box.add_child(right)
	stats_box = VBoxContainer.new(); stats_box.add_theme_constant_override("separation", 8); right.add_child(stats_box)
	var bar := HBoxContainer.new(); bar.add_theme_constant_override("separation", 14)
	bar.anchor_left = 0.5; bar.anchor_right = 0.5; bar.anchor_top = 1; bar.anchor_bottom = 1
	bar.offset_left = -230; bar.offset_right = 230; bar.offset_top = -82; bar.offset_bottom = -16; bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(_reg(_button("⟵ Zurück", func(): main.show_title(), false)))
	var go := _button("Zum Startplatz 🚀", func(): main.hangar_launch())
	bar.add_child(go)
	hangar_box.set_meta("go", go)
	hangar_box.add_child(bar)

func set_go_text(t: String) -> void:
	(hangar_box.get_meta("go") as Button).text = T.t(t)

func build_rows(rows: Array, sel: int, value_of: Callable, change: Callable) -> void:
	for c in rows_box.get_children():
		c.queue_free()
	var si := 0
	for r in rows:
		if r.k == "head":
			var h := _label(String(r.label).to_upper(), 15, Color(1, 1, 1, 0.65)); rows_box.add_child(h); continue
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _style(Color(1, 0.82, 0.25, 0.22) if si == sel else Color(1, 1, 1, 0.07), 12, Color(0, 0, 0, 0), SUN if si == sel else Color(0, 0, 0, 0)))
		pc.mouse_filter = Control.MOUSE_FILTER_PASS
		var hb := HBoxContainer.new(); hb.mouse_filter = Control.MOUSE_FILTER_PASS; pc.add_child(hb)
		var lab := _label(r.label, 19); lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(lab)
		var rr: Dictionary = r
		var idx := si
		var minus := _button("−", func(): change.call(idx, rr, -1), false, 22); minus.custom_minimum_size = Vector2(46, 42); hb.add_child(minus)
		var val := _label(value_of.call(rr), 19); val.custom_minimum_size = Vector2(100, 0); val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hb.add_child(val)
		var plus := _button("+", func(): change.call(idx, rr, 1), false, 22); plus.custom_minimum_size = Vector2(46, 42); hb.add_child(plus)
		rows_box.add_child(pc)
		si += 1

func build_stats(st: Dictionary, need: String) -> void:
	for c in stats_box.get_children():
		c.queue_free()
	stats_box.add_child(_label(T.t("📊 Was kann sie?"), 28))
	var twr_ok: bool = st.twr >= 1.2
	var twr_mid: bool = st.twr >= 1.0
	stats_box.add_child(_label(T.t("💪 Abheben: stark" if twr_ok else ("💪 Abheben: knapp" if twr_mid else "💪 Abheben: zu schwer")), 20))
	stats_box.add_child(_bar(clampf(st.twr / 2.5, 0.0, 1.0), GO if twr_ok else (SUN if twr_mid else Color(1, 0.35, 0.37)), []))
	stats_box.add_child(_label(T.t("🛣️ Reichweite"), 20))
	var mk := [[Parts.NEED.space / 2300.0, "🌤"], [Parts.NEED.orbit / 2300.0, "🌍"], [Parts.NEED.moon / 2300.0, "🌙"]]
	stats_box.add_child(_bar(clampf(st.dv / 2300.0, 0.0, 1.0), GO, mk))
	var spacer := Control.new(); spacer.custom_minimum_size = Vector2(0, 26); stats_box.add_child(spacer)
	stats_box.add_child(_label(T.t("Gewicht: %s t · Höhe: %d m") % [_g(st.mass), int(st.height)], 17, Color(1, 1, 1, 0.85)))
	var verdict := ""
	if not twr_mid:
		verdict = T.t("❌ Zu schwer – sie hebt nicht ab! Nimm einen großen Motor oder Booster.")
	elif need != "" and st.dv < Parts.NEED[need]:
		verdict = T.t("⚠️ Reicht noch nicht %s. Mehr Tanks oder eine zweite Stufe!") % T.t({"space": "bis in den Weltraum", "orbit": "für den Orbit", "moon": "bis zum Mond"}[need])
	elif need != "":
		verdict = T.t("✅ Super! Die schafft %s.") % T.t({"space": "den Weltraum", "orbit": "den Orbit", "moon": "den Mond"}[need])
	else:
		verdict = T.t("✅ Fertig zum Start!")
	var vl := _label(verdict, 18); vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; vl.custom_minimum_size = Vector2(300, 0)
	stats_box.add_child(vl)

func _bar(frac: float, col: Color, marks: Array) -> Control:
	var c := Control.new(); c.custom_minimum_size = Vector2(300, 26)
	c.draw.connect(_draw_bar.bind(c, frac, col, marks))
	return c

func _draw_bar(c: Control, frac: float, col: Color, marks: Array) -> void:
	var w := c.size.x
	c.draw_rect(Rect2(0, 0, w, 22), Color(1, 1, 1, 0.12), true)
	c.draw_rect(Rect2(0, 0, w * frac, 22), col, true)
	for m in marks:
		var x: float = w * m[0]
		c.draw_line(Vector2(x, -6), Vector2(x, 28), Color(1, 1, 1, 0.6), 3.0)
		c.draw_string(font, Vector2(x - 14, 54), m[1], HORIZONTAL_ALIGNMENT_CENTER, 28, 22)

func _on_button(cb: Callable) -> void:
	main.audio.sfx("click")
	cb.call()

func _on_card(idx: int) -> void:
	main.audio.sfx("click")
	main.begin_mission(idx)

func _toggle_sound() -> void:
	main.audio.set_on(not main.audio.on)
	_update_sound_btn()

func _pause_restart() -> void:
	main.toggle_pause(false)
	main.restart_mission()

func _pause_menu() -> void:
	main.toggle_pause(false)
	main.show_title()

# =====================================================================
#  Cockpit
# =====================================================================
func _build_hud() -> void:
	hud_box = Control.new(); _full(hud_box); hud_box.theme = theme_main; hud_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hud_box)
	var mb := PanelContainer.new(); mb.add_theme_stylebox_override("panel", _glass()); mb.position = Vector2(12, 12); mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mv := VBoxContainer.new(); mb.add_child(mv)
	m_title = _label("", 24); mv.add_child(m_title)
	m_obj = _label("", 18, SUN); m_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; m_obj.custom_minimum_size = Vector2(380, 0); mv.add_child(m_obj)
	hud_box.add_child(mb)
	var tp := PanelContainer.new(); tp.add_theme_stylebox_override("panel", _glass()); tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.anchor_left = 1; tp.anchor_right = 1; tp.offset_left = -270; tp.offset_right = -12; tp.offset_top = 12
	tele = _label("", 19); tp.add_child(tele); hud_box.add_child(tp)
	var sp := PanelContainer.new(); sp.add_theme_stylebox_override("panel", _glass()); sp.position = Vector2(12, 130); sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stages_lbl = _label("", 17); sp.add_child(stages_lbl); hud_box.add_child(sp)
	hud_box.set_meta("stages_panel", sp)
	keys_lbl = _label("", 20, SUN); keys_lbl.anchor_left = 0.5; keys_lbl.anchor_right = 0.5; keys_lbl.offset_left = -300; keys_lbl.offset_right = 300; keys_lbl.offset_top = 14
	keys_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8)); keys_lbl.add_theme_constant_override("shadow_offset_y", 2)
	hud_box.add_child(keys_lbl)
	warp_lbl = _label("", 24, Color(0.5, 0.89, 1.0)); warp_lbl.anchor_left = 0.5; warp_lbl.anchor_right = 0.5; warp_lbl.offset_left = -200; warp_lbl.offset_right = 200; warp_lbl.offset_top = 52
	warp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hud_box.add_child(warp_lbl)
	big_lbl = _label("", 140, Color.WHITE); _full(big_lbl); big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; big_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_lbl.offset_bottom = -200; big_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6)); big_lbl.add_theme_constant_override("shadow_offset_y", 6)
	big_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_box.add_child(big_lbl)
	navball = Control.new(); navball.size = Vector2(170, 170); navball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navball.draw.connect(_draw_navball); hud_box.add_child(navball)
	map = Control.new(); map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.draw.connect(_draw_map); hud_box.add_child(map)
	var pause_btn := _button("⏸", func(): main.toggle_pause(true), false, 22); pause_btn.position = Vector2(0, 0)
	pause_btn.anchor_left = 1; pause_btn.anchor_right = 1; pause_btn.offset_left = -330; pause_btn.offset_right = -282; pause_btn.offset_top = 14
	hud_box.add_child(pause_btn)
	touch = preload("res://scripts/touch.gd").new(); touch.ui = self; _full(touch); add_child(touch)
	_place_map()

func _place_map() -> void:
	var vs := get_viewport().get_visible_rect().size
	var ms := minf(vs.x, vs.y) * 0.84 if map_big else 240.0
	map.size = Vector2(ms, ms)
	map.position = (vs - map.size) / 2.0 if map_big else Vector2(vs.x - ms - 12, vs.y - ms - 12)
	navball.position = Vector2(12, vs.y - 182)
	if touch:
		touch.relayout(vs, map.get_rect(), navball.get_rect())

func toggle_map() -> void:
	map_big = not map_big; _place_map(); main.audio.sfx("click")

func big_msg(t: String, small := false) -> void:
	big_lbl.text = T.t(t)
	big_lbl.add_theme_font_size_override("font_size", 64 if small else 140)
	big_lbl.modulate.a = 1.0; _big_t = 0.9

func _process(dt: float) -> void:
	if _big_t > 0.0:
		_big_t -= dt
		if _big_t <= 0.0:
			big_lbl.modulate.a = 0.0
	if hud_box.visible:
		navball.queue_redraw(); map.queue_redraw(); touch.queue_redraw()

func update_hud(f) -> void:
	var b = f.cam_body()
	if b == null:
		return
	var r: float = sqrt(b.x * b.x + b.y * b.y)
	var alt := r - P.R
	var sp: float = sqrt(b.vx * b.vx + b.vy * b.vy)
	var el := P.elements(b.x, b.y, b.vx, b.vy)
	var s := T.t("Höhe  %s km\nTempo  %s km/h") % [P.fmt_km(alt), P.fmt_kmh(sp)]
	var landed := false
	if f.vessel != null and b == f.vessel:
		landed = f.vessel.landed
	if not el.esc and sp > 150.0 and not landed:
		s += "\n" + T.t("▲ Hochpunkt  %s") % ("—" if el.ap > P.RM else P.fmt_km(el.ap) + " km")
		s += "\n" + T.t("▼ Tiefpunkt  %s") % (T.t("im Boden") if el.pe < 0.0 else P.fmt_km(el.pe) + " km")
	elif el.esc:
		s += "\n" + T.t("Fliegt weg von der Erde!")
	var vv = f.vessel
	if vv != null and b == vv and not vv.landed:
		s += "\n" + T.t("G-Kraft  %s g  (max %s)") % [_g(vv.g_load), _g(vv.g_max)]
	if f.M and f.M.map_moon:
		var ma := P.moon_angle(f.t)
		var dm: float = sqrt(pow(b.x - P.RM * cos(ma), 2.0) + pow(b.y - P.RM * sin(ma), 2.0))
		s += "\n" + T.t("Bis zum Mond  %d %%") % int(dm / P.RM * 100.0)
	if sci_on and vv != null and f.dock.is_empty():
		var m_t: float = vv.mass() / 1000.0
		var twr: float = vv.thrust_n / maxf(1.0, vv.mass() * P.G0) if vv.firing() else 0.0
		s += "\n" + T.t("— 🔬 Raketen-Daten —")
		s += "\n" + T.t("Schub  %d kN") % int(vv.thrust_n / 1000.0 if vv.firing() else 0.0)
		s += "\n" + T.t("Gewicht  %s t") % _g(m_t)
		s += "\n" + T.t("Schub ÷ Gewicht  %s") % _g(twr)
		s += "\n" + T.t("Reichweite übrig  %d m/s") % int(vv.dv_left())
		s += "\n" + T.t("Luftdruck (Q)  %s kPa") % _g(vv.q / 1000.0)
	if f.M:
		var ex: String = f.M.hud_extra()
		if ex != "":
			s += "\n" + ex
	tele.text = s
	var st := ""
	var v = f.vessel
	if v != null and f.dock.is_empty():
		for i in range(v.st.size() - 1, v.s - 1, -1):
			var sd: Dictionary = v.st[i]
			st += "%s %d  %s\n" % ["▶" if i == v.s else " ", i + 1, _fuel_bar(sd.fuel / sd.fuel0)]
			if i == 0 and v.boost:
				st += "▶ B  %s\n" % _fuel_bar(sd.b_fuel / sd.b_fuel0)
		st += T.t("🧑‍🚀 Kapsel") + (" + 🪂" if v.chute else "")
	elif f.iss != null and f.iss.get("tug") != null:
		st = "⛽ %s\n" % _fuel_bar(f.iss.tug.fuel) + T.t("🛰 Bremsschiff")
	stages_lbl.text = st
	(hud_box.get_meta("stages_panel") as Control).visible = st != ""
	warp_lbl.text = T.t("⏩ Zeitraffer ×%d") % int(round(f.warp)) if f.warp > 1.05 else ""
	m_obj.text = T.t(f.objective)
	var kt := ""
	for k in f.keys_hint:
		kt += ("  ●" if k[1] else "  ") + " " + T.t(k[0]) + "  "
	keys_lbl.text = kt

func _g(x: float) -> String:
	return T.dec1(x)

func _fuel_bar(x: float) -> String:
	var n := int(round(clampf(x, 0.0, 1.0) * 10.0))
	return "█".repeat(n) + "░".repeat(10 - n)

# ---------- Richtungsanzeige ----------
func _draw_navball() -> void:
	var f = main.flight
	var c := navball
	var cen := Vector2(85, 85)
	var rr := 75.0
	c.draw_circle(cen, rr + 6, Color(0.04, 0.06, 0.13, 0.8))
	var v = f.vessel
	if v == null:
		return
	if not f.dock.is_empty():
		_draw_dock_aid(c, cen, rr, f.dock)
		return
	# Himmel oben, Boden unten
	var sky := PackedVector2Array()
	var ground := PackedVector2Array()
	for i in 33:
		var a := PI + float(i) / 32.0 * PI
		sky.append(cen + Vector2(cos(a), sin(a)) * rr)
		ground.append(cen + Vector2(cos(a - PI), sin(a - PI)) * rr)
	c.draw_colored_polygon(sky, Color(0.25, 0.55, 0.92))
	c.draw_colored_polygon(ground, Color(0.55, 0.36, 0.2))
	c.draw_line(cen - Vector2(rr, 0), cen + Vector2(rr, 0), Color.WHITE, 3.0)
	c.draw_arc(cen, rr, 0, TAU, 48, Color(1, 1, 1, 0.7), 4.0)
	var up: float = atan2(v.y, v.x)
	var sp: float = sqrt(v.vx * v.vx + v.vy * v.vy)
	var at := func(a: float) -> Vector2:
		var rel := P.ang_diff(a, up)
		return cen + Vector2(sin(rel), -cos(rel)) * rr * 0.72
	if sp > 3.0 and not v.landed:
		var pro: float = atan2(v.vy, v.vx)
		var pp: Vector2 = at.call(pro)
		c.draw_arc(pp, 8, 0, TAU, 20, GO, 3.0)
		c.draw_line(pp - Vector2(15, 0), pp - Vector2(8, 0), GO, 3.0); c.draw_line(pp + Vector2(8, 0), pp + Vector2(15, 0), GO, 3.0)
		var rp: Vector2 = at.call(pro + PI)
		c.draw_arc(rp, 8, 0, TAU, 20, Color(1, 0.48, 0.35), 3.0)
		c.draw_line(rp - Vector2(5, 5), rp + Vector2(5, 5), Color(1, 0.48, 0.35), 3.0); c.draw_line(rp + Vector2(5, -5), rp - Vector2(5, -5), Color(1, 0.48, 0.35), 3.0)
	if f.show_guide and not is_nan(f.guide_hd):
		_star(c, at.call(f.guide_hd), 13.0)
	var rel: float = P.ang_diff(v.hd, up)
	var dir := Vector2(sin(rel), -cos(rel))
	var side := Vector2(-dir.y, dir.x)
	var body := PackedVector2Array([cen + dir * 44, cen + dir * 18 + side * 9, cen - dir * 20 + side * 9, cen - dir * 20 - side * 9, cen + dir * 18 - side * 9])
	c.draw_colored_polygon(body, Color.WHITE)
	c.draw_polyline(body + PackedVector2Array([body[0]]), INK, 2.5)
	c.draw_colored_polygon(PackedVector2Array([cen - dir * 8 + side * 9, cen - dir * 24 + side * 17, cen - dir * 20 + side * 9]), Color(0.9, 0.22, 0.27))
	c.draw_colored_polygon(PackedVector2Array([cen - dir * 8 - side * 9, cen - dir * 24 - side * 17, cen - dir * 20 - side * 9]), Color(0.9, 0.22, 0.27))
	if v.firing():
		c.draw_colored_polygon(PackedVector2Array([cen - dir * 21 + side * 6, cen - dir * randf_range(36, 44), cen - dir * 21 - side * 6]), Color(1, 0.72, 0.01))

func _star(c: Control, p: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var t := Time.get_ticks_msec() / 1200.0
	for i in 10:
		var a := float(i) / 10.0 * TAU - PI / 2.0 + t
		pts.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, SUN)

func _draw_dock_aid(c: Control, cen: Vector2, rr: float, d: Dictionary) -> void:
	c.draw_circle(cen, rr, Color(0.04, 0.07, 0.19))
	c.draw_arc(cen, 22, 0, TAU, 32, SUN, 4.0)
	c.draw_line(cen - Vector2(rr, 0), cen + Vector2(rr, 0), Color(1, 1, 1, 0.3), 1.5)
	c.draw_line(cen - Vector2(0, rr), cen + Vector2(0, rr), Color(1, 1, 1, 0.3), 1.5)
	var rel: Vector3 = d.rel
	var p := cen + Vector2(clampf(rel.x * 16.0, -rr, rr), clampf(-rel.y * 16.0, -rr, rr))
	var ok := absf(rel.x) < 0.8 and absf(rel.y) < 0.8
	c.draw_circle(p, 9, GO if ok else Color(1, 0.48, 0.35))
	c.draw_string(font, cen + Vector2(-50, rr - 8), "%d m" % int(maxf(0.0, rel.z)), HORIZONTAL_ALIGNMENT_CENTER, 100, 20)

# ---------- Karte ----------
func _draw_map() -> void:
	var f = main.flight
	var c := map
	var S := c.size.x
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.02, 0.04, 0.11, 0.92), true)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.15), false, 2.0)
	c.draw_string(font, Vector2(10, 24), T.t("🗺 Karte"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
	var body = f.cam_body()
	if body == null:
		return
	var pr: Dictionary = f.pred
	var max_r: float = sqrt(body.x * body.x + body.y * body.y) * 1.12
	if pr.has("max_r"):
		max_r = maxf(max_r, minf(pr.max_r, P.RM * 1.3) * 1.08)
	if f.M and f.M.map_moon:
		max_r = maxf(max_r, P.RM + P.RMOON * 3.0)
	max_r = maxf(max_r, P.R * 1.35)
	var s := (S / 2.0 - 10.0) / max_r
	var o := c.size / 2.0
	var X := func(x: float, y: float) -> Vector2: return o + Vector2(x * s, -y * s)
	# Atmosphäre und Erde
	c.draw_circle(o, maxf((P.R + P.ATM) * s, P.R * s + 4.0), Color(0.43, 0.7, 1.0, 0.28))
	c.draw_circle(o, P.R * s, Color(0.12, 0.38, 0.72))
	var seg := 180
	for i in seg:
		var a0 := float(i) / seg * TAU
		if P.is_land_at(a0 + PI / seg):
			c.draw_arc(o, P.R * s * 0.89, -a0 - TAU / seg, -a0, 3, Color(0.25, 0.62, 0.29), P.R * s * 0.22)
	# Nachtseite
	var sa := atan2(P.sun_dir().y, P.sun_dir().x)
	var night := PackedVector2Array([o])
	for i in 33:
		var a := -sa + PI / 2.0 + float(i) / 32.0 * PI
		night.append(o + Vector2(cos(a), sin(a)) * (P.R * s + 1.0))
	c.draw_colored_polygon(night, Color(0, 0, 0.04, 0.45))
	# Startplatz
	var sp0: Vector2 = X.call(0.0, P.R)
	c.draw_line(sp0, sp0 - Vector2(0, 16), SUN, 3.0)
	c.draw_colored_polygon(PackedVector2Array([sp0 - Vector2(0, 16), sp0 - Vector2(-13, 12), sp0 - Vector2(0, 8)]), SUN)
	if f.M:
		f.M.map_draw(c, X, s)
	# Mond
	var ma := P.moon_angle(f.t)
	var mp: Vector2 = X.call(P.RM * cos(ma), P.RM * sin(ma))
	if Rect2(Vector2.ZERO, c.size).grow(20).has_point(mp):
		c.draw_arc(o, P.RM * s, 0, TAU, 96, Color(1, 1, 1, 0.12), 1.0)
		c.draw_circle(mp, maxf(6.0, P.RMOON * s), Color(0.79, 0.79, 0.79))
		c.draw_string(font, mp + Vector2(-30, -maxf(10.0, P.RMOON * s) - 6), T.t("Mond"), HORIZONTAL_ALIGNMENT_CENTER, 60, 16)
	if pr.get("left_earth", false) and pr.has("moon_min_t") and f.M and f.M.map_moon:
		var ga := P.moon_angle(f.t + pr.moon_min_t)
		var gp: Vector2 = X.call(P.RM * cos(ga), P.RM * sin(ga))
		c.draw_circle(gp, maxf(6.0, P.RMOON * s), Color(0.79, 0.79, 0.79, 0.4))
		c.draw_string(font, gp + Vector2(-90, maxf(10.0, P.RMOON * s) + 18), T.t("Mond dann"), HORIZONTAL_ALIGNMENT_CENTER, 180, 15, Color(1, 1, 1, 0.65))
	# ISS
	if f.iss != null and f.iss.node.visible:
		var ib: Dictionary = f.iss
		if not ib.dynamic:
			c.draw_arc(o, ib.r * s, 0, TAU, 128, Color(0.5, 0.89, 1.0, 0.3), 2.0)
		var ip: Vector2 = X.call(ib.x, ib.y)
		c.draw_rect(Rect2(ip - Vector2(9, 2), Vector2(18, 4)), Color(0.5, 0.89, 1.0))
		c.draw_rect(Rect2(ip - Vector2(2, 6), Vector2(4, 12)), Color(0.5, 0.89, 1.0))
		c.draw_string(font, ip + Vector2(-20, -12), "ISS", HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(0.5, 0.89, 1.0))
	for d in f.debris:
		if d.alive and d.kind == "iss":
			c.draw_rect(Rect2(X.call(d.x, d.y) - Vector2(2, 2), Vector2(4, 4)), Color(1, 0.7, 0.42))
	# Flugbahn
	if pr.has("pts") and pr.pts.size() > 3:
		var pts: PackedVector2Array = pr.pts
		var impact = pr.get("impact", null)
		var col := GO
		if impact != null:
			col = Color(1, 0.35, 0.37) if (impact.land and f.M and f.M.land_bad) else Color(1, 0.7, 0.42)
		var line := PackedVector2Array()
		var step := maxi(1, pts.size() / 600)
		for i in range(0, pts.size(), step):
			line.append(X.call(pts[i].x, pts[i].y))
		c.draw_polyline(line, col, 3.5, true)
		if impact != null:
			var ip: Vector2 = X.call(impact.x, impact.y)
			var k := 10.0 + sin(Time.get_ticks_msec() / 120.0) * 2.0
			var xc: Color = f.M.x_color() if f.M else Color(1, 0.23, 0.23)
			c.draw_line(ip - Vector2(k, k), ip + Vector2(k, k), Color.BLACK, 8.0); c.draw_line(ip + Vector2(k, -k), ip - Vector2(k, -k), Color.BLACK, 8.0)
			c.draw_line(ip - Vector2(k, k), ip + Vector2(k, k), xc, 5.0); c.draw_line(ip + Vector2(k, -k), ip - Vector2(k, -k), xc, 5.0)
	# Hoch- und Tiefpunkt
	var fb = null
	if f.vessel != null and not f.vessel.landed and f.dock.is_empty():
		fb = f.vessel
	elif f.iss != null and f.iss.dynamic:
		fb = f.iss
	if fb != null and sqrt(fb.vx * fb.vx + fb.vy * fb.vy) > 200.0:
		var el := P.elements(fb.x, fb.y, fb.vx, fb.vy)
		if not el.esc and el.e > 0.004 and el.ap < P.RM * 0.5:
			_flag(c, X, el.ap_a, el.ap + P.R, "▲ " + P.fmt_km(el.ap) + " km", Color(0.5, 0.89, 1.0))
			if el.pe > -P.R * 0.9:
				_flag(c, X, el.pe_a, el.pe + P.R, "▼ " + P.fmt_km(el.pe) + " km", Color(1, 0.7, 0.42))
	# Raumschiff
	if f.vessel != null and f.cam_target == null:
		var v = f.vessel
		var vp: Vector2 = X.call(v.x, v.y)
		var d := Vector2(cos(v.hd), -sin(v.hd))
		var sd := Vector2(-d.y, d.x)
		c.draw_colored_polygon(PackedVector2Array([vp + d * 14, vp - d * 8 + sd * 8, vp - d * 8 - sd * 8]), Color.WHITE)
		c.draw_arc(vp, 18 + sin(Time.get_ticks_msec() / 200.0) * 3.0, 0, TAU, 24, Color(1, 1, 1, 0.55), 2.0)

func _flag(c: Control, X: Callable, a: float, rr: float, txt: String, col: Color) -> void:
	var p: Vector2 = X.call(cos(a) * rr, sin(a) * rr)
	c.draw_circle(p, 6, col)
	var tp := p + Vector2(cos(a), -sin(a)) * 24.0 + Vector2(-50, 6)
	c.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 100, 17, 5, Color(0, 0, 0, 0.7))
	c.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 100, 17, col)

# =====================================================================
#  Mira, Ergebnis, Pause, Wissen
# =====================================================================
func _build_caption() -> void:
	caption = PanelContainer.new(); caption.theme = theme_main
	caption.add_theme_stylebox_override("panel", _style(CARD, 22, EDGE))
	caption.anchor_left = 0.5; caption.anchor_right = 0.5; caption.anchor_top = 1; caption.anchor_bottom = 1
	caption.offset_left = -330; caption.offset_right = 330; caption.offset_top = -120; caption.offset_bottom = -14
	caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 12); caption.add_child(hb)
	var face := Control.new(); face.custom_minimum_size = Vector2(70, 70)
	face.draw.connect(func(): _draw_mira(face))
	hb.add_child(face)
	cap_text = _label("", 21, INK); cap_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; cap_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(cap_text)
	add_child(caption)
	caption.visible = false

func _draw_mira(c: Control) -> void:
	var o := Vector2(35, 35)
	c.draw_circle(o, 34, Color(0.17, 0.25, 0.43))
	c.draw_circle(o + Vector2(0, 26), 22, Color(1, 0.48, 0.0))
	c.draw_circle(o + Vector2(0, -2), 16, Color(0.96, 0.82, 0.71))
	c.draw_arc(o + Vector2(0, -4), 17, PI, TAU, 16, Color(0.42, 0.24, 0.12), 8.0)
	c.draw_circle(o + Vector2(-6, 0), 2.2, INK); c.draw_circle(o + Vector2(6, 0), 2.2, INK)
	c.draw_arc(o + Vector2(0, 5), 5, 0.2, PI - 0.2, 8, INK, 2.0)
	c.draw_arc(o + Vector2(0, -2), 19, PI, TAU, 16, INK, 3.0)
	c.draw_rect(Rect2(o + Vector2(-21, -6), Vector2(6, 11)), INK); c.draw_rect(Rect2(o + Vector2(15, -6), Vector2(6, 11)), INK)

func _place_caption(screen := "") -> void:
	if caption == null:
		return
	var top := touch != null and touch.visible
	if screen == "hangar":
		# über der Knopfleiste (Zurück / Zum Startplatz), damit sie frei bleibt
		caption.anchor_left = 1; caption.anchor_right = 1; caption.offset_left = -430; caption.offset_right = -18
		caption.anchor_top = 1; caption.anchor_bottom = 1; caption.offset_top = -190; caption.offset_bottom = -96
		caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
		return
	caption.anchor_left = 0.5; caption.anchor_right = 0.5; caption.offset_left = -330; caption.offset_right = 330
	if top:
		caption.anchor_top = 0; caption.anchor_bottom = 0; caption.offset_top = 92; caption.offset_bottom = 190
		caption.grow_vertical = Control.GROW_DIRECTION_END
	else:
		caption.anchor_top = 1; caption.anchor_bottom = 1; caption.offset_top = -120; caption.offset_bottom = -14
		caption.grow_vertical = Control.GROW_DIRECTION_BEGIN

func show_caption(text: String) -> void:
	cap_text.text = text
	caption.visible = true

func _center_card(parent: Control) -> VBoxContainer:
	var shade := ColorRect.new(); _full(shade); shade.color = Color(0.01, 0.02, 0.05, 0.75); parent.add_child(shade)
	var cc := CenterContainer.new(); _full(cc); parent.add_child(cc)
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", _style(CARD, 30, EDGE)); pc.custom_minimum_size = Vector2(560, 0)
	cc.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); pc.add_child(v)
	return v

func _build_result() -> void:
	result_box = Control.new(); _full(result_box); result_box.theme = theme_main; add_child(result_box)
	var v := _center_card(result_box)
	r_icon = _label("⭐", 70, INK); r_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(r_icon)
	r_title = _label("", 38, INK); r_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; r_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(r_title)
	r_facts = _label("", 20, INK); r_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; r_facts.custom_minimum_size = Vector2(520, 0); v.add_child(r_facts)
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 12); v.add_child(hb)
	r_next = _button("Weiter", func(): main.result_next()); hb.add_child(r_next)
	r_again = _reg(_button("Nochmal", func(): main.restart_mission(), false)); hb.add_child(r_again)
	hb.add_child(_reg(_button("Menü", func(): main.show_title(), false)))

func show_result(ok: bool, icon: String, title: String, facts: Array, has_next: bool) -> void:
	r_icon.text = icon; r_title.text = T.t(title)
	var t := ""
	if facts.is_empty():
		t = T.t("• Probier es gleich nochmal – du schaffst das!")
	else:
		for x in facts:
			t += "• " + T.t(x) + "\n"
	r_facts.text = t.strip_edges()
	r_next.text = T.t("Nächste Mission ➜" if (ok and has_next) else ("Zum Menü" if ok else "Nochmal versuchen"))
	r_again.visible = ok

func _build_pause() -> void:
	pause_box = Control.new(); _full(pause_box); pause_box.theme = theme_main; add_child(pause_box)
	var v := _center_card(pause_box)
	var t: Label = _reg(_label("⏸ Pause", 40, INK)); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 12); v.add_child(hb)
	hb.add_child(_reg(_button("Weiterfliegen", func(): main.toggle_pause(false))))
	hb.add_child(_reg(_button("Neu starten", _pause_restart, false)))
	hb.add_child(_reg(_button("Menü", _pause_menu, false)))
	var help: Label = _reg(_label("Tastatur: Leertaste Motor · A/D drehen · W vor · S zurück · Enter Stufe · F Zeitraffer · M Karte · C Kamera · B Bordcomputer · T Ton", 16, Color(INK, 0.75)))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; help.custom_minimum_size = Vector2(520, 0); v.add_child(help)

func _build_facts() -> void:
	facts_box = Control.new(); _full(facts_box); facts_box.theme = theme_main; add_child(facts_box)
	var v := _center_card(facts_box)
	var t: Label = _reg(_label("📒 Raumfahrt-Wissen", 36, INK)); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(620, 420); v.add_child(sc)
	var lbl := _label("", 19, INK); lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lbl.custom_minimum_size = Vector2(600, 0); sc.add_child(lbl)
	facts_box.set_meta("lbl", lbl)
	v.add_child(_reg(_button("Zurück", func(): main.show_title())))

func fill_facts(done: Dictionary) -> void:
	var t := ""
	for m in Missions.LIST:
		if done.get(m.id, false):
			t += "%s %s\n" % [m.icon, T.t(m.title)]
			for x in Missions.FACTS[m.id]:
				t += "   • " + T.t(x) + "\n"
			t += "\n"
		else:
			t += T.t("%s %s: noch nicht geschafft") % [m.icon, T.t(m.title)] + "\n\n"
	(facts_box.get_meta("lbl") as Label).text = t
