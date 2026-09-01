## Synthèse des sons de course — aucun fichier audio dans le dépôt.
##
## **Pourquoi synthétiser plutôt qu'embarquer des fichiers.** Le projet n'a pas
## d'assets audio, et la règle du dépôt est de ne rien télécharger pour
## construire. Tout le reste est déjà fabriqué en code — la piste, les coureurs,
## les shaders : le son suit la même règle. Un bip est une sinusoïde et une
## cloche est une somme de partiels ; les écrire prend moins de place qu'un seul
## `.ogg`, et rien ne peut manquer à l'export.
##
## **Pourquoi c'est du `RefCounted` sans dépendance.** Ce fichier ne produit que
## des `AudioStreamWAV`, c'est-à-dire des données. Il se teste en headless, sans
## carte son et sans serveur audio — exactement comme `core/`.
class_name SoundForge
extends RefCounted

const MIX_RATE := 44100
## Marge sous le plein niveau. Une somme de partiels dépasse facilement 1.0 ;
## écrêter produit un craquement, ce qui est le contraire de l'effet voulu.
const HEADROOM := 0.86


## Bip de décompte : une sinusoïde courte, attaque nette et chute rapide.
##
## Une sinusoïde pure et brève est ce qui perce le mieux le bruit d'une salle,
## et c'est ce que fait n'importe quel starter électronique.
static func beep(hertz: float = 880.0, seconds: float = 0.12) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		# Attaque de 4 ms : sans elle, le saut de zéro à pleine amplitude
		# produit un clic aussi fort que le bip lui-même.
		var attack := minf(t / 0.004, 1.0)
		var decay := exp(-t * 14.0)
		samples[i] = sin(TAU * hertz * t) * attack * decay
	return _wav(samples, false)


## Klaxon de départ : deux sinusoïdes légèrement désaccordées, plus une quinte.
##
## Le désaccord fait battre le son, ce qui lui donne du corps ; une sinusoïde
## seule sonnerait comme un bip long, et le départ doit s'entendre autrement que
## le décompte.
static func horn(seconds: float = 0.75) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		var attack := minf(t / 0.008, 1.0)
		var release := minf((seconds - t) / 0.06, 1.0)
		var body := (
			sin(TAU * 392.0 * t)
			+ sin(TAU * 394.5 * t) * 0.9
			+ sin(TAU * 588.0 * t) * 0.45
		)
		samples[i] = body / 2.35 * attack * maxf(release, 0.0)
	return _wav(samples, false)


## Cloche des derniers mètres : partiels INHARMONIQUES à décroissance séparée.
##
## C'est ce qui distingue une cloche d'un orgue : ses partiels ne sont pas des
## multiples entiers de la fondamentale, et les aigus s'éteignent les premiers.
static func bell(seconds: float = 1.8) -> AudioStreamWAV:
	var partials := [
		[1.00, 1.00, 2.2], [2.76, 0.55, 3.4], [5.40, 0.30, 5.1], [8.93, 0.16, 7.0]
	]
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		var value := 0.0
		for partial: Array in partials:
			value += (
				sin(TAU * 784.0 * float(partial[0]) * t)
				* float(partial[1])
				* exp(-t * float(partial[2]))
			)
		samples[i] = value / 2.0 * minf(t / 0.002, 1.0)
	return _wav(samples, false)


## Réaction de foule : bruit filtré qui enfle puis retombe.
##
## Une foule n'a pas de hauteur : c'est du bruit. Le filtre passe-bas lui donne
## sa masse, et l'enveloppe en cloche son mouvement — la clameur monte, elle
## n'apparaît pas.
static func crowd(seconds: float = 1.4, seed_value: int = 20260901) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	var band := 0.0
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		# Deux passe-bas en cascade : un seul laisse un souffle trop sifflant.
		low = lerpf(low, white, 0.12)
		band = lerpf(band, low, 0.35)
		var swell := sin(PI * clampf(t / seconds, 0.0, 1.0))
		samples[i] = band * swell * 3.2
	return _wav(samples, false)


## Nappe de fond, en boucle. Trois sinusoïdes graves battant lentement.
##
## La durée est choisie pour contenir un nombre ENTIER de périodes de chaque
## partiel : c'est la seule façon d'avoir une boucle sans clic, sans recourir à
## un fondu qui atténuerait le son au raccord.
static func drone(seconds: float = 2.0) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		var value := (
			sin(TAU * 55.0 * t)
			+ sin(TAU * 82.5 * t) * 0.55
			+ sin(TAU * 110.0 * t) * 0.35
			+ sin(TAU * 165.0 * t) * 0.12
		)
		samples[i] = value / 2.02 * 0.7
	return _wav(samples, true)


## Souffle de vent, en boucle : bruit filtré, raccordé par fondu croisé.
##
## Le bruit n'a pas de période : aucune durée ne donne une boucle propre. On
## génère donc un peu plus long que nécessaire et on fond la queue sur la tête.
static func wind(seconds: float = 2.0, seed_value: int = 424242) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var blend := int(0.25 * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var raw := PackedFloat32Array()
	raw.resize(frames + blend)
	var low := 0.0
	for i: int in range(raw.size()):
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.06)
		raw[i] = low * 4.0

	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i: int in range(frames):
		samples[i] = raw[i]
	for i: int in range(blend):
		var mix := float(i) / float(blend)
		samples[i] = lerpf(raw[frames + i], raw[i], mix)
	return _wav(samples, true)


## Encode des échantillons flottants en `AudioStreamWAV` 16 bits mono.
##
## La normalisation est faite ICI et pour tout le monde : chaque générateur peut
## viser l'expressivité sans compter ses décimales, et rien ne sort écrêté.
static func _wav(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	var gain := HEADROOM / peak if peak > 0.0001 else 0.0

	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
