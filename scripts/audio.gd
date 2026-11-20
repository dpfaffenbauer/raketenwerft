extends Node
## Ton: Miras Sprache, Geräusche, Dauerschleifen (Triebwerk, Wind, Hitze), Musik.

const L := preload("res://scripts/lines.gd")

var on := true
var voice: AudioStreamPlayer
var music: AudioStreamPlayer
var loops := {}
var pool: Array[AudioStreamPlayer] = []
var cache := {}
var voice_until := 0.0
var music_kind := ""
var _music_target := 0.0

func _ready() -> void:
	voice = AudioStreamPlayer.new(); voice.volume_db = 0.0; add_child(voice)
	music = AudioStreamPlayer.new(); music.volume_db = -14.0; add_child(music)
	for n in ["engine", "hiss", "wind", "heat"]:
		var p := AudioStreamPlayer.new()
		p.stream = _wav("loop_" + n, true)
		p.volume_db = -80.0
		add_child(p)
		p.play()
		loops[n] = p
	for i in 8:
		var p := AudioStreamPlayer.new(); add_child(p); pool.append(p)
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		on = cfg.get_value("audio", "on", true)
	_apply_mute()

func _wav(name: String, loop := false) -> AudioStream:
	var key := name + ("_loop" if loop else "")
	if cache.has(key):
		return cache[key]
	var path := "res://audio/sfx/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStreamWAV = load(path)
	if loop:
		s = s.duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	cache[key] = s
	return s

func set_on(v: bool) -> void:
	on = v
	# vorhandene Einstellungen laden, damit der Abschnitt "ui" (Sprache) erhalten bleibt
	var cfg := ConfigFile.new(); cfg.load("user://settings.cfg"); cfg.set_value("audio", "on", on); cfg.save("user://settings.cfg")
	_apply_mute()

func _apply_mute() -> void:
	AudioServer.set_bus_mute(0, not on)

func sfx(name: String, vol_db := 0.0) -> void:
	var s := _wav(name)
	if s == null:
		return
	for p in pool:
		if not p.playing:
			p.stream = s; p.volume_db = vol_db; p.play(); return
	pool[0].stream = s; pool[0].volume_db = vol_db; pool[0].play()

## Mira sagt etwas (in der eingestellten Sprache). Gibt die Länge in Sekunden zurück.
func say(id: String) -> float:
	var text: String = L.text(id)
	var path := L.voice_path(id)
	var dur := maxf(3.0, text.length() * 0.07)
	if ResourceLoader.exists(path):
		var st: AudioStream = load(path)
		voice.stream = st
		voice.play()
		dur = st.get_length() + 0.3
	voice_until = Time.get_ticks_msec() / 1000.0 + dur
	return dur

func speaking() -> bool:
	return voice.playing or Time.get_ticks_msec() / 1000.0 < voice_until

func stop_voice() -> void:
	voice.stop(); voice_until = 0.0

func _db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func engine(power: float, pressure: float) -> void:
	var air := 0.12 + 0.88 * pressure
	_loop("engine", power * air * 1.1)
	_loop("hiss", power * 0.18 * air)

func wind(q: float, heat: float) -> void:
	_loop("wind", clamp(q / 25000.0, 0.0, 1.0) * 0.5)
	_loop("heat", heat * 0.7)

func _loop(n: String, v: float) -> void:
	var p: AudioStreamPlayer = loops[n]
	var target := _db(v)
	p.volume_db = lerp(p.volume_db, target, 0.15) if target > -79.0 else max(-80.0, p.volume_db - 3.0)

func set_music(kind: String) -> void:
	if kind == music_kind:
		return
	music_kind = kind
	if kind == "":
		music.stop(); return
	var s := _wav("music_" + kind, true)
	if s:
		music.stream = s; music.play()

func _process(_dt: float) -> void:
	# Musik leiser, während Mira spricht
	var target := -22.0 if voice.playing else -14.0
	music.volume_db = lerp(music.volume_db, target, 0.05)
