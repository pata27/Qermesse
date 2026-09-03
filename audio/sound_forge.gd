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
## Partiels d'une cloche, en multiples INHARMONIQUES de la fondamentale :
## rapport, poids, vitesse d'extinction. Partagés par la cloche et le glas.
## Formants d'une foule qui crie, et leur poids. Ce sont des voix, pas du bruit.
const ROAR_FORMANTS: Array[float] = [500.0, 1200.0, 2600.0]
const ROAR_WEIGHTS: Array[float] = [1.0, 0.6, 0.28]
const BELL_PARTIALS := [
	[1.00, 1.00, 2.0], [2.76, 0.55, 3.2], [5.40, 0.30, 4.8], [8.93, 0.16, 6.6]
]


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


## UNE FRAPPE de cloche, ajoutée dans `samples` à partir de `start`.
##
## Partiels INHARMONIQUES à décroissance séparée : c'est ce qui distingue une
## cloche d'un orgue. Ses partiels ne sont pas des multiples entiers de la
## fondamentale, et les aigus s'éteignent les premiers.
static func _strike(
	samples: PackedFloat32Array, start: int, hertz: float, gain: float, decay: float
) -> void:
	for i: int in range(start, samples.size()):
		var t := float(i - start) / MIX_RATE
		var value := 0.0
		for partial: Array in BELL_PARTIALS:
			value += (
				sin(TAU * hertz * float(partial[0]) * t)
				* float(partial[1])
				* exp(-t * float(partial[2]) * decay)
			)
		# LE BATTANT. Un choc de métal commence par un bruit, pas par une note :
		# sans ces quelques millisecondes de transitoire, la cloche s'entend
		# comme un bip long — et c'est exactement le reproche qui lui a été
		# fait.
		var clapper := exp(-t * 220.0) * sin(TAU * 3100.0 * t) * 0.5
		samples[i] += (value + clapper) * gain * minf(t / 0.001, 1.0)


## Cloche de vélodrome : une VOLÉE, pas un coup.
##
## Sur piste, la fin se dit à la cloche, agitée plusieurs fois — c'est le signal
## que tout coureur reconnaît. Un coup unique se prend pour un bip ; la volée ne
## se confond avec rien. Les frappes faiblissent et se rapprochent légèrement,
## comme une cloche qu'on secoue.
static func bell(seconds: float = 3.0, strikes: int = 4) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	# LES COUPS INTERMEDIAIRES S'ETEIGNENT VITE, le dernier resonne. C'est ce
	# que fait une cloche qu'on agite : chaque coup coupe le precedent, et le
	# dernier reste. Des coups a decroissance egale se recouvraient en une
	# bouillie ou l'on n'entendait plus qu'une frappe et demie.
	#
	# Et les gains ne descendent pas regulierement : une main qui secoue une
	# cloche ne frappe pas deux fois pareil. C'est cette irregularite qui la
	# fait entendre comme un objet et non comme une boucle.
	var gains := [1.0, 0.88, 0.96, 1.0]
	for strike: int in range(strikes):
		var last := strike == strikes - 1
		_strike(
			samples,
			int(float(strike) * 0.32 * MIX_RATE),
			784.0,
			float(gains[strike % gains.size()]),
			0.7 if last else 2.6
		)
	return _wav(samples, false)


## Glas d'élimination : une frappe grave, longue, sans reprise.
##
## Une élimination est le contraire d'une clameur — c'est quelqu'un qui sort.
## Même timbre que la cloche, deux octaves plus bas et sans volée : la salle
## comprend qu'il s'agit du même monde sonore, et que ce n'est pas la même
## nouvelle.
static func knell(seconds: float = 2.4) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	_strike(samples, 0, 196.0, 1.0, 0.45)
	return _wav(samples, false)


## Souffle de dépassement : un bruit qui passe, du grave vers l'aigu.
##
## La clameur dit que la salle a réagi ; le souffle dit ce qui s'est passé sur
## la piste. Le balayage du filtre donne le mouvement — quelque chose est passé,
## et dans un sens.
static func whoosh(seconds: float = 0.55, seed_value: int = 91137) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	var band := 0.0
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		var phase := t / seconds
		var cutoff := lerpf(260.0, 2100.0, phase * phase)
		var f := 2.0 * sin(PI * cutoff / MIX_RATE)
		var high := rng.randf_range(-1.0, 1.0) - low - band * 0.5
		band += f * high
		low += f * band
		# Enveloppe en cloche : le souffle passe, il n'apparaît pas.
		samples[i] = band * sin(PI * clampf(phase, 0.0, 1.0)) * 1.4
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


## LE GRONDEMENT DES ROULEAUX — le son propre du goldsprint.
##
## C'est ce qu'on entend vraiment dans une salle : un rugissement de pneu sur
## acier, continu, qui monte avec la vitesse. Il manquait, et sans lui la course
## n'avait aucun fond audible — la nappe grave, elle, ne sort d'aucun
## haut-parleur d'ordinateur (docs/04 §6, règle des haut-parleurs).
##
## Deux résonances : le corps vers 320 Hz, la matière vers 780. Un filtre à
## variable d'état donne la résonance qu'un simple passe-bas ne peut pas
## produire — c'est elle qui fait entendre du METAL et non du souffle.
##
## La modulation lente est le roulement lui-même : un rouleau n'est jamais
## parfaitement rond, et cette irrégularité est ce qui distingue un rouleau
## d'un ventilateur.
static func rollers(seconds: float = 2.0, seed_value: int = 705019) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var blend := int(0.25 * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var raw := PackedFloat32Array()
	raw.resize(frames + blend)
	var f_body := 2.0 * sin(PI * 320.0 / MIX_RATE)
	var f_grain := 2.0 * sin(PI * 780.0 / MIX_RATE)
	var low_body := 0.0
	var band_body := 0.0
	var low_grain := 0.0
	var band_grain := 0.0
	for i: int in range(raw.size()):
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		var high_body := white - low_body - band_body * 0.22
		band_body += f_body * high_body
		low_body += f_body * band_body
		var high_grain := white - low_grain - band_grain * 0.5
		band_grain += f_grain * high_grain
		low_grain += f_grain * band_grain
		var roll := 1.0 + sin(TAU * 7.3 * t) * 0.18 + sin(TAU * 11.7 * t) * 0.10
		raw[i] = (band_body * 1.0 + band_grain * 0.35) * roll * 2.4

	return _wav(_seam(raw, frames, blend), true)


## RUMEUR DE SALLE, en boucle. Une foule qui attend n'est pas silencieuse.
##
## Distincte de la clameur ponctuelle : celle-ci est un événement, celle-là un
## décor. Bruit très filtré, fluctuant lentement — assez présent pour que le
## silence n'existe jamais, assez neutre pour laisser passer les clameurs.
static func crowd_bed(seconds: float = 3.0, seed_value: int = 314159) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var blend := int(0.4 * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var raw := PackedFloat32Array()
	raw.resize(frames + blend)
	var low := 0.0
	var band := 0.0
	var f := 2.0 * sin(PI * 520.0 / MIX_RATE)
	for i: int in range(raw.size()):
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		var high := white - low - band * 0.85
		band += f * high
		low += f * band
		# Trois houles lentes et incommensurables : la rumeur respire sans
		# jamais se repeter a l'oreille.
		var swell := 1.0 + sin(TAU * 0.37 * t) * 0.25 + sin(TAU * 0.61 * t) * 0.18
		raw[i] = (low + band * 0.4) * swell * 2.0

	return _wav(_seam(raw, frames, blend), true)


## Raccorde une boucle par fondu croisé de la queue sur la tête.
##
## Le bruit n'a pas de période : aucune durée ne donne une boucle propre. On
## génère donc `blend` échantillons de plus et on les fond sur le début.
static func _seam(raw: PackedFloat32Array, frames: int, blend: int) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i: int in range(frames):
		samples[i] = raw[i]
	for i: int in range(blend):
		samples[i] = lerpf(raw[frames + i], raw[i], float(i) / float(blend))
	return samples


## LA CLAMEUR DE L'ARRIVEE. Pas une réaction : une explosion.
##
## Distincte de `crowd()`, qui dure une seconde et demie et sert aux petits
## faits de course. Ici la salle hurle — c'est le moment de la soirée, et il
## doit s'entendre comme tel : attaque immédiate, plateau tenu, longue
## retombée.
##
## Trois bandes de formants au lieu d'un bruit filtré. Une foule qui crie n'est
## pas du souffle : ce sont des VOIX, et une voix a des formants — autour de
## 500, 1200 et 2600 Hz. Sans eux on obtient une cascade, pas des gens.
static func roar(seconds: float = 4.5, seed_value: int = 660613) -> AudioStreamWAV:
	var frames := int(seconds * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var lows := [0.0, 0.0, 0.0]
	var bands := [0.0, 0.0, 0.0]
	var coefficients: Array[float] = []
	for hertz: float in ROAR_FORMANTS:
		coefficients.append(2.0 * sin(PI * hertz / MIX_RATE))
	for i: int in range(frames):
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		var value := 0.0
		for k: int in range(ROAR_FORMANTS.size()):
			var high: float = white - lows[k] - bands[k] * 0.55
			bands[k] += coefficients[k] * high
			lows[k] += coefficients[k] * bands[k]
			value += bands[k] * float(ROAR_WEIGHTS[k])
		# L'enveloppe : trois centièmes pour monter — la salle explose, elle
		# n'enfle pas —, un plateau, puis une longue retombée. Et une houle
		# irrégulière par-dessus : des milliers de gens ne crient jamais
		# ensemble.
		var attack := minf(t / 0.03, 1.0)
		var release := 1.0 if t < seconds * 0.35 else exp(-(t - seconds * 0.35) * 1.3)
		var surge := 1.0 + sin(TAU * 1.7 * t) * 0.18 + sin(TAU * 3.1 * t) * 0.12
		samples[i] = value * attack * release * surge * 2.6
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
		# LES PARTIELS HAUTS NE SONT PAS UN ORNEMENT. Mesuree, la premiere
		# version plaçait 90 % de son energie sous 200 Hz — sous ce qu'un
		# haut-parleur d'ordinateur restitue. Elle n'existait tout simplement
		# pas sur les machines qui font tourner ce logiciel. 220, 330 et 440 Hz
		# la rendent audible sans changer ce qu'elle raconte : les graves
		# portent encore la fondamentale la ou une vraie sono la restitue.
		var value := (
			sin(TAU * 55.0 * t) * 0.30
			+ sin(TAU * 110.0 * t) * 0.32
			+ sin(TAU * 220.0 * t) * 0.85
			+ sin(TAU * 330.0 * t) * 0.5
			+ sin(TAU * 440.0 * t) * 0.28
			+ sin(TAU * 660.0 * t) * 0.12
		)
		samples[i] = value / 2.4 * 0.7
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

	return _wav(_seam(raw, frames, blend), true)


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
