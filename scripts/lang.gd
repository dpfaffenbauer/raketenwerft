extends RefCounted
## Sprache: Deutsch ("de") oder Englisch ("en").
## Alle Texte im Code bleiben deutsch; t("deutscher Text") liefert auf Englisch die Übersetzung aus EN.
## Fehlt eine Übersetzung, bleibt der deutsche Text stehen (und wird einmal im Log gemeldet).
## Gespeichert in user://settings.cfg, Abschnitt "ui", Schlüssel "lang".
## Für Tests: Godot --path . -- --lang=en   (überschreibt die Einstellung, ohne sie zu speichern)

const SETTINGS := "user://settings.cfg"

static var lang := ""
static var _missing := {}

static func _ensure() -> void:
	if lang != "":
		return
	lang = "de" if OS.get_locale_language() == "de" else "en"
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		lang = String(cfg.get_value("ui", "lang", lang))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.substr(7)
	if lang != "de" and lang != "en":
		lang = "en"

static func current() -> String:
	_ensure()
	return lang

static func en() -> bool:
	_ensure()
	return lang == "en"

## Sprache setzen und speichern (andere Abschnitte der Datei, z. B. "audio", bleiben erhalten).
static func set_lang(l: String) -> void:
	lang = l
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "lang", l)
	cfg.save(SETTINGS)

static func toggle() -> void:
	set_lang("de" if en() else "en")

## Übersetzen: deutscher Text rein, Text in der eingestellten Sprache raus.
static func t(de: String) -> String:
	if not en() or de == "":
		return de
	if EN.has(de):
		return EN[de]
	if not _missing.has(de) and de.to_lower() != de.to_upper():   # nur Texte mit Buchstaben melden
		_missing[de] = true
		print("LANG fehlt: ", de)
	return de

## Zahl mit Tausenderpunkt (de: 5.700) bzw. Tausenderkomma (en: 5,700).
static func thousands_sep() -> String:
	return "," if en() else "."

## Kommazahl mit einer Stelle (de: 2,6 / en: 2.6).
static func dec1(x: float) -> String:
	var s := "%.1f" % x
	return s if en() else s.replace(".", ",")

## Englische Texte, Schlüssel = deutscher Text genau wie im Code.
const EN := {
	# --- Titel ---
	"Pauls Raketenwerft": "Paul's Rocket Workshop",
	"Bau deine Rakete, flieg in den Orbit, besuch die ISS – und bring sie sicher nach Hause!": "Build your rocket, fly into orbit, visit the ISS – and bring it safely home!",
	"🔊 Ton": "🔊 Sound",
	"🔊 Ton an": "🔊 Sound on",
	"🔇 Ton aus": "🔇 Sound off",
	"📒 Wissen": "📒 Facts",
	# --- Missionen ---
	"Erster Flug": "First Flight",
	"Bau eine Rakete und flieg ins Weltall – und mit dem Fallschirm zurück.": "Build a rocket and fly into space – and back down by parachute.",
	"Rund um die Erde": "Around the Earth",
	"Flieg so schnell zur Seite, dass du nicht mehr runterfällst!": "Fly sideways so fast that you don't fall down anymore!",
	"Sicher nach Hause": "Safely Home",
	"Bremsen, glühen, Fallschirm – und Platsch ins Meer.": "Brake, glow, parachute – and splash into the sea.",
	"Besuch bei der ISS": "Visiting the ISS",
	"Hol die Raumstation ein und dock an.": "Catch up with the space station and dock.",
	"Die ISS kommt heim": "The ISS Comes Home",
	"Bremse die alte ISS genau zum Punkt Nemo.": "Steer the old ISS down right to Point Nemo.",
	"Um den Mond herum": "Around the Moon",
	"Die große Reise: zum Mond und wieder zurück!": "The big journey: to the Moon and back again!",
	"Freies Fliegen": "Free Flight",
	"Bau, was du willst, und flieg, wohin du willst.": "Build what you want, and fly where you want.",
	# --- Wissen ---
	"Die Erde zieht alles zu sich hin. Das heißt Schwerkraft.": "The Earth pulls everything toward it. That's called gravity.",
	"Ab 100 km Höhe beginnt der Weltraum.": "Space begins 100 km up.",
	"Oben ist der Himmel schwarz, weil dort keine Luft das Sonnenlicht verteilt.": "Up there the sky is black, because there's no air to spread the sunlight around.",
	"Ein Fallschirm bremst, weil er ganz viel Luft fängt.": "A parachute slows you down because it catches lots of air.",
	"Orbit heißt: Man fällt die ganze Zeit – aber so schnell zur Seite, dass man immer an der Erde vorbeifällt.": "Orbit means: you're falling all the time – but so fast sideways that you keep falling past the Earth.",
	"Dafür braucht man 28.000 km/h – 100-mal so schnell wie ein Auto.": "For that you need 28,000 km/h – 100 times as fast as a car.",
	"Raketen fliegen erst hoch und kippen dann zur Seite.": "Rockets first fly up and then tip over to the side.",
	"Leere Stufen wirft man ab, dann ist die Rakete leichter.": "Empty stages get dropped, so the rocket is lighter.",
	"Am Hochpunkt Gas geben hebt die andere Seite der Bahn an.": "Giving gas at the high point lifts the other side of the path.",
	"Um runterzukommen, bremst man gegen die Flugrichtung.": "To come down, you brake against the direction you're flying.",
	"Beim Eintauchen in die Luft wird es über 1500 Grad heiß – die Luft glüht!": "Diving into the air gets hotter than 1,500 degrees – the air glows!",
	"Der Hitzeschild schützt die Astronauten.": "The heat shield protects the astronauts.",
	"Dann bremsen Fallschirme, und ein Schiff holt die Kapsel aus dem Meer.": "Then parachutes slow it down, and a ship picks the capsule up out of the sea.",
	"Die ISS ist so groß wie ein Fußballfeld und fliegt 400 km hoch.": "The ISS is as big as a football field and flies 400 km high.",
	"Seit dem Jahr 2000 wohnen dort immer Astronauten.": "Astronauts have lived there all the time since the year 2000.",
	"Komischer Trick: Wer tiefer fliegt, ist schneller und holt auf.": "Funny trick: whoever flies lower is faster and catches up.",
	"Beim Andocken fliegt man ganz langsam – nur ein paar Zentimeter pro Sekunde.": "When docking, you fly very slowly – just a few centimeters per second.",
	"Die ISS wird um 2030 von einem Bremsschiff nach unten geschoben.": "Around 2030, a braking ship will push the ISS down.",
	"Sie fällt in den Pazifik beim Punkt Nemo – dem Ort, der am weitesten von allen Menschen entfernt ist.": "It will fall into the Pacific at Point Nemo – the place farthest away from all people.",
	"Dort liegen schon viele alte Raumschiffe – ein Raumschiff-Friedhof.": "Lots of old spacecraft already lie there – a spaceship graveyard.",
	"Die meisten Teile verglühen in der Luft wie Sternschnuppen.": "Most of the pieces burn up in the air like shooting stars.",
	"Der echte Mond ist 384.000 km weit weg. Die Apollo-Astronauten brauchten 3 Tage dorthin.": "The real Moon is 384,000 km away. The Apollo astronauts needed 3 days to get there.",
	"Mit dem richtigen Schwung zieht der Mond die Rakete herum und schickt sie zurück: die freie Rückkehr.": "With just the right swing, the Moon pulls the rocket around and sends it back: the free return.",
	"Vom Mond aus sieht die Erde ganz klein und blau aus.": "From the Moon, the Earth looks very small and blue.",
	"Zurück kommt man sehr schnell an – darum glüht der Hitzeschild besonders stark.": "Coming back, you arrive very fast – that's why the heat shield glows extra hot.",
	"Du kannst alles ausprobieren: Orbit, ISS, Mond!": "You can try everything: orbit, ISS, Moon!",
	"Knopf Computer: Der Bordcomputer fliegt dich in den Orbit.": "Computer button: the flight computer flies you into orbit.",
	"Tipp auf die Karte für die große Ansicht.": "Tap the map for the big view.",
	"📒 Raumfahrt-Wissen": "📒 Space Facts",
	"%s %s: noch nicht geschafft": "%s %s: not done yet",
	# --- Werft ---
	"🔧 Baukasten": "🔧 Build Kit",
	"Hüpfer": "Hopper",
	"Orbit-Rakete": "Orbit Rocket",
	"Mond-Rakete": "Moon Rocket",
	"⟵ Zurück": "⟵ Back",
	"Zum Startplatz 🚀": "To the Launch Pad 🚀",
	"Trotzdem starten 🚀": "Launch Anyway 🚀",
	"Rakete": "Rocket",
	"Anzahl Stufen": "Stages",
	"Stufe %d": "Stage %d",
	" (unten)": " (bottom)",
	"⛽ Tanks": "⛽ Tanks",
	"🔥 Motor": "🔥 Engine",
	"🚀 Booster": "🚀 Boosters",
	"🔺 Flossen": "🔺 Fins",
	"Aussehen": "Looks",
	"🎨 Farbe": "🎨 Color",
	"%d Stück": "%d",
	"keine": "none",
	"ja": "yes",
	"nein": "no",
	"Klein": "Small",
	"Groß": "Big",
	"Weltraum": "Space",
	"Rot": "Red",
	"Blau": "Blue",
	"Grün": "Green",
	"Gelb": "Yellow",
	"Lila": "Purple",
	"Schwarz": "Black",
	"📊 Was kann sie?": "📊 What can it do?",
	"💪 Abheben: stark": "💪 Liftoff: strong",
	"💪 Abheben: knapp": "💪 Liftoff: just barely",
	"💪 Abheben: zu schwer": "💪 Liftoff: too heavy",
	"🛣️ Reichweite": "🛣️ Range",
	"Gewicht: %s t · Höhe: %d m": "Weight: %s t · Height: %d m",
	"❌ Zu schwer – sie hebt nicht ab! Nimm einen großen Motor oder Booster.": "❌ Too heavy – it won't lift off! Take a big engine or boosters.",
	"⚠️ Reicht noch nicht %s. Mehr Tanks oder eine zweite Stufe!": "⚠️ Can't make it %s yet. More tanks or a second stage!",
	"bis in den Weltraum": "to space",
	"für den Orbit": "to orbit",
	"bis zum Mond": "to the Moon",
	"✅ Super! Die schafft %s.": "✅ Super! It can make it %s.",
	"den Weltraum": "to space",
	"den Orbit": "to orbit",
	"den Mond": "to the Moon",
	"✅ Fertig zum Start!": "✅ Ready for launch!",
	# --- Cockpit ---
	"Höhe  %s km\nTempo  %s km/h": "Altitude  %s km\nSpeed  %s km/h",
	"▲ Hochpunkt  %s": "▲ High point  %s",
	"▼ Tiefpunkt  %s": "▼ Low point  %s",
	"im Boden": "underground",
	"Fliegt weg von der Erde!": "Flying away from Earth!",
	"G-Kraft  %s g  (max %s)": "G-force  %s g  (max %s)",
	"Bis zum Mond  %d %%": "To the Moon  %d %%",
	"— 🔬 Raketen-Daten —": "— 🔬 Rocket Data —",
	"Schub  %d kN": "Thrust  %d kN",
	"Gewicht  %s t": "Weight  %s t",
	"Schub ÷ Gewicht  %s": "Thrust ÷ Weight  %s",
	"Reichweite übrig  %d m/s": "Range left  %d m/s",
	"Luftdruck (Q)  %s kPa": "Air pressure (Q)  %s kPa",
	"🧑‍🚀 Kapsel": "🧑‍🚀 Capsule",
	"🛰 Bremsschiff": "🛰 Braking ship",
	"⏩ Zeitraffer ×%d": "⏩ Fast-forward ×%d",
	"🗺 Karte": "🗺 Map",
	"Mond": "Moon",
	"Mond dann": "Moon later",
	"KLACK!": "CLUNK!",
	"START!": "LIFTOFF!",
	"Seite": "Side",
	"Schräg": "Angled",
	"Weit": "Far",
	"Ganz weit": "Very far",
	# Touch-Knöpfe
	"Zurück": "Back",
	"Vor": "Forward",
	"MOTOR": "ENGINE",
	"Stufe ab": "Stage",
	"Kamera": "Camera",
	"Computer": "Computer",
	"🔬 Wissen": "🔬 Science",
	# --- Ziele und Tasten-Hinweise ---
	"Motor = Countdown ⏱": "Engine = countdown ⏱",
	"Drück den Motor-Knopf zum Starten": "Press the engine button to launch",
	"Countdown …": "Countdown …",
	"Motor halten 🔥": "Hold engine 🔥",
	"Flieg zum goldenen Stern, bis der Hochpunkt 400 km erreicht": "Fly toward the golden star until the high point reaches 400 km",
	"▶ kippen": "▶ tilt",
	"◀ kippen": "◀ tilt",
	"Motor 🔥": "Engine 🔥",
	"Computer fliegt": "Computer is flying",
	"Warte bis ganz oben (Zeitraffer ⏩)": "Wait until the very top (fast-forward ⏩)",
	"⏩ halten": "⏩ hold",
	"Karte": "Map",
	"Gas geben, bis der Tiefpunkt aus der Luft raus ist": "Give gas until the low point is out of the air",
	"Bumm! Nochmal probieren": "Boom! Try again",
	"Flieg in den Weltraum – über 100 km hoch!": "Fly into space – higher than 100 km!",
	"Jetzt sicher landen!": "Now land safely!",
	"Du bist im Orbit! 🎉": "You're in orbit! 🎉",
	"⏩ Zeitraffer": "⏩ Fast-forward",
	"Dreh die Rakete nach hinten": "Turn the rocket around backwards",
	"Zurück ⤺": "Back ⤺",
	"Bremsen, bis die Linie in die Luft taucht": "Brake until the line dips into the air",
	"Motor = bremsen 🔥": "Engine = brake 🔥",
	"Nach Hause fallen …": "Falling home …",
	"Hol die ISS ein!": "Catch up with the ISS!",
	"Ein kleines bisschen bremsen": "Brake just a tiny bit",
	"Warten und aufholen (⏩ Zeitraffer)": "Wait and catch up (⏩ fast-forward)",
	"Andocken am gelben Ring": "Dock at the yellow ring",
	"◀ ▶ ▲ ▼ zielen": "◀ ▶ ▲ ▼ aim",
	"Motor = langsam vor": "Engine = slowly forward",
	"Die alte ISS": "The old ISS",
	"⏩ halten: Die Station sinkt langsam": "⏩ hold: the station slowly sinks",
	"Das Bremsschiff kommt": "The braking ship is coming",
	"Bring das rote Kreuz ins gelbe Ziel": "Get the red cross into the yellow target",
	"Vor = bisschen Gas": "Forward = a little gas",
	"Die Station fällt …": "The station is falling …",
	"Warten, bis du beim grünen Pfeil bist": "Wait until you reach the green arrow",
	"Gas geben – der Bordcomputer sagt, wann es reicht": "Give gas – the flight computer says when it's enough",
	"Beim Mond! 🌙": "At the Moon! 🌙",
	"Auf dem Weg zum Mond (⏩ Zeitraffer)": "On the way to the Moon (⏩ fast-forward)",
	"Nachsteuern, bis die Linie die Erde trifft": "Steer until the line hits the Earth",
	"Heimflug zur Erde (⏩ Zeitraffer)": "Flying home to Earth (⏩ fast-forward)",
	"Abstand ISS  %d km": "Distance to ISS  %d km",
	"🎯 Punkt Nemo": "🎯 Point Nemo",
	"hier bremsen": "brake here",
	"Start zum Mond": "Moon launch",
	# --- Ergebnis ---
	"Du warst im Weltraum!": "You were in space!",
	"Fast! Noch höher fliegen": "Almost! Fly even higher",
	"Du bist im Orbit!": "You're in orbit!",
	"Zurück auf der Erde – noch mehr Tempo zur Seite!": "Back on Earth – more speed sideways!",
	"Sicher gelandet!": "Landed safely!",
	"Angedockt an der ISS!": "Docked with the ISS!",
	"Die ISS ist beim Punkt Nemo!": "The ISS is at Point Nemo!",
	"Im Meer – aber nicht ganz beim Punkt Nemo": "In the sea – but not quite at Point Nemo",
	"Teile sind auf Land gefallen": "Pieces fell on land",
	"Einmal Mond und zurück!": "To the Moon and back!",
	"Wieder auf der Erde – ab zum Mond beim nächsten Mal!": "Back on Earth – off to the Moon next time!",
	"Weiter": "Next",
	"Nochmal": "Again",
	"Menü": "Menu",
	"• Probier es gleich nochmal – du schaffst das!": "• Try again right away – you can do it!",
	"Nächste Mission ➜": "Next Mission ➜",
	"Zum Menü": "To the Menu",
	"Nochmal versuchen": "Try Again",
	# --- Pause ---
	"⏸ Pause": "⏸ Pause",
	"Weiterfliegen": "Keep Flying",
	"Neu starten": "Restart",
	"Tastatur: Leertaste Motor · A/D drehen · W vor · S zurück · Enter Stufe · F Zeitraffer · M Karte · C Kamera · B Bordcomputer · T Ton": "Keyboard: Space engine · A/D turn · W forward · S back · Enter stage · F fast-forward · M map · C camera · B flight computer · T sound",
}
