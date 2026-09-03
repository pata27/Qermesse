## Musique de course — synthétisée, en couches superposables.
##
## **Pourquoi une musique.** Une course dure vingt secondes et il ne s'y passe
## presque aucun événement : sans musique, le public entend un fond et attend.
## Une salle de goldsprint est une fête, et une fête a une bande-son.
##
## **Pourquoi trois couches et non un morceau.** C'est le remix vertical, la
## méthode habituelle du jeu vidéo : trois boucles de MÊME durée, jouées
## ensemble en permanence, dont on ne fait varier que le volume. La musique suit
## alors la course — une pulsation seule au départ, la batterie quand ça
## s'emballe, le thème quand ça se décide — sans jamais couper ni redémarrer,
## donc sans jamais trahir le montage. Un morceau linéaire, lui, se serait
## désynchronisé de la course dès la première course courte.
##
## **Pourquoi une seule mesure de durée pour les trois.** Elles tournent en
## boucle côte à côte : la moindre différence de longueur les ferait glisser
## l'une sur l'autre en quelques secondes.
class_name MusicForge
extends RefCounted

const MIX_RATE := SoundForge.MIX_RATE
## 150 à la noire : le tempo d'un sprint. Deux mesures à quatre temps font
## 3,2 s, soit 141 120 échantillons — un compte ENTIER, donc une boucle sans
## clic et sans fondu.
const BPM := 150.0
const BEAT_S := 60.0 / BPM
const BARS := 2
const BEATS := BARS * 4
const LOOP_S := BEATS * BEAT_S

## La ligne de basse, en demi-tons sous le la 220. Mineur, insistant : deux
## mesures qui tournent sans jamais se résoudre, ce qui est exactement ce qu'on
## veut sous une course — de la tension qui ne retombe pas.
const BASS_STEPS := [0, 0, 12, 0, -2, -2, 10, -2]
## Le thème, en demi-tons au-dessus du la 440, sur une pentatonique mineure.
const LEAD_STEPS := [0, 7, 3, 10, 12, 10, 7, 3]

## Podium : 100 à la noire, quatre mesures. 9,6 s, soit 423 360 échantillons —
## un compte entier, donc une boucle sans clic comme les autres.
const ANTHEM_BEAT_S := 60.0 / 100.0
const ANTHEM_BARS := 4
## Do, sol, la mineur, fa — en demi-tons depuis le la. La marche la plus
## naturellement montante qui soit, et elle retombe sur elle-même.
const ANTHEM_ROOTS := [3, -2, 0, -4]
const ANTHEM_MINOR := [false, false, true, false]


static func _frames() -> int:
	return int(LOOP_S * MIX_RATE)


## Hauteur d'un degré chromatique au-dessus d'une référence.
static func _hertz(root: float, semitones: float) -> float:
	return root * pow(2.0, semitones / 12.0)


## COUCHE 1 — la pulsation. Grosse caisse et basse, présentes du départ à
## l'arrivée. C'est le pouls de la course : il ne s'arrête jamais.
static func pulse() -> AudioStreamWAV:
	var frames := _frames()
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for beat: int in range(BEATS):
		var start := int(beat * BEAT_S * MIX_RATE)
		_kick(samples, start)
		_bass(samples, start, _hertz(110.0, float(BASS_STEPS[beat])), BEAT_S * 0.92)
	return _loop(samples)


## COUCHE 2 — l'emballement. Charleston sur les contretemps et claquement sur
## les temps faibles : c'est ce qui donne la vitesse. Monte quand la course
## s'emballe, disparaît quand elle traîne.
static func drive() -> AudioStreamWAV:
	var frames := _frames()
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for beat: int in range(BEATS):
		var start := int(beat * BEAT_S * MIX_RATE)
		# Deux croches par temps, la seconde plus forte : c'est le contretemps
		# qui fait avancer, pas le temps.
		_hat(samples, start, 0.35)
		_hat(samples, start + int(BEAT_S * 0.5 * MIX_RATE), 0.75)
		if beat % 4 == 2:
			_clap(samples, start)
	return _loop(samples)


## COUCHE 3 — le thème. Un arpège brillant, qui n'entre que dans les moments
## qui comptent : la fin de course, un écart qui se creuse.
static func lead() -> AudioStreamWAV:
	var frames := _frames()
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for beat: int in range(BEATS):
		var start := int(beat * BEAT_S * MIX_RATE)
		var hertz := _hertz(440.0, float(LEAD_STEPS[beat]))
		_pluck(samples, start, hertz, BEAT_S * 0.85)
		# L'octave au-dessus, deux fois plus courte, sur la croche : l'arpège
		# scintille au lieu de marteler.
		_pluck(samples, start + int(BEAT_S * 0.5 * MIX_RATE), hertz * 2.0, BEAT_S * 0.3)
	return _loop(samples)


## LA MUSIQUE DU PODIUM. Autre tempo, autre mode, autre propos.
##
## La musique de course est mineure et ne se résout jamais : c'est de la tension
## qui ne retombe pas, ce qu'on veut sous une course. Un podium demande
## exactement l'inverse — une résolution. D'où le majeur, un tempo plus lent, et
## une marche d'accords qui retombe sur elle-même : do, sol, la mineur, fa.
##
## Quatre mesures et non deux : le classement reste à l'écran jusqu'au départ
## suivant, parfois une minute. Une boucle courte s'entendrait comme une boucle.
static func anthem() -> AudioStreamWAV:
	var beats := ANTHEM_BARS * 4
	var frames := int(float(beats) * ANTHEM_BEAT_S * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for bar: int in range(ANTHEM_BARS):
		var root: float = float(ANTHEM_ROOTS[bar])
		var third: float = 3.0 if bool(ANTHEM_MINOR[bar]) else 4.0
		for beat: int in range(4):
			var start := int((float(bar * 4 + beat)) * ANTHEM_BEAT_S * MIX_RATE)
			# Le pied sur les temps FORTS seulement : un podium se marche, il ne
			# se court pas.
			if beat % 2 == 0:
				_kick(samples, start)
				_bass(samples, start, _hertz(110.0, root), ANTHEM_BEAT_S * 1.8)
			# L'accord s'égrène : fondamentale, tierce, quinte, octave — un
			# arpège monte, et c'est ce qui s'entend comme une victoire.
			var degree: float = [0.0, third, 7.0, 12.0][beat]
			_pluck(samples, start, _hertz(440.0, root + degree), ANTHEM_BEAT_S * 1.4)
			_pluck(
				samples, start, _hertz(220.0, root + degree), ANTHEM_BEAT_S * 1.4
			)
	return _loop(samples)


## Grosse caisse : une sinusoïde dont la hauteur PLONGE. C'est la chute de
## fréquence qui fait le coup de pied ; à hauteur fixe on n'entend qu'un bourdon.
static func _kick(samples: PackedFloat32Array, start: int) -> void:
	var length := int(0.26 * MIX_RATE)
	var phase := 0.0
	for i: int in range(length):
		var index := start + i
		if index >= samples.size():
			return
		var t := float(i) / MIX_RATE
		var hertz := 48.0 + 120.0 * exp(-t * 42.0)
		phase += TAU * hertz / MIX_RATE
		# Le claquement du battant, deux millisecondes : sans lui, la caisse ne
		# perce pas un haut-parleur d'ordinateur.
		var click := exp(-t * 500.0) * 0.5
		samples[index] += (sin(phase) * exp(-t * 9.0) + click) * 0.95


## Basse : une dent de scie adoucie, filtrée. La scie donne les harmoniques qui
## la rendent audible ailleurs que sur un caisson.
static func _bass(samples: PackedFloat32Array, start: int, hertz: float, seconds: float) -> void:
	var length := int(seconds * MIX_RATE)
	var low := 0.0
	for i: int in range(length):
		var index := start + i
		if index >= samples.size():
			return
		var t := float(i) / MIX_RATE
		var saw := fmod(t * hertz, 1.0) * 2.0 - 1.0
		low = lerpf(low, saw, 0.22)
		var envelope := minf(t / 0.005, 1.0) * exp(-t * 2.4)
		samples[index] += low * envelope * 0.55


## Charleston : bruit très court, aigu.
static func _hat(samples: PackedFloat32Array, start: int, gain: float) -> void:
	var length := int(0.05 * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + start
	var previous := 0.0
	for i: int in range(length):
		var index := start + i
		if index >= samples.size():
			return
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		# Passe-haut à un pôle : la différence de deux échantillons voisins.
		var high := white - previous
		previous = white
		samples[index] += high * exp(-t * 120.0) * gain * 0.35


## Claquement de mains : trois bouffées rapprochées, puis une queue. C'est la
## répétition qui fait entendre des MAINS et non un bruit blanc.
static func _clap(samples: PackedFloat32Array, start: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + start
	var low := 0.0
	var length := int(0.30 * MIX_RATE)
	for i: int in range(length):
		var index := start + i
		if index >= samples.size():
			return
		var t := float(i) / MIX_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.45)
		var envelope := exp(-t * 22.0) * 0.55
		for echo: float in [0.0, 0.011, 0.023]:
			if t >= echo:
				envelope += exp(-(t - echo) * 190.0) * 0.9
		samples[index] += low * envelope * 0.5


## Note du thème : deux scies légèrement désaccordées. Le désaccord fait vibrer
## la note — une scie seule sonne comme un buzzer.
static func _pluck(
	samples: PackedFloat32Array, start: int, hertz: float, seconds: float
) -> void:
	var length := int(seconds * MIX_RATE)
	var low := 0.0
	for i: int in range(length):
		var index := start + i
		if index >= samples.size():
			return
		var t := float(i) / MIX_RATE
		var a := fmod(t * hertz, 1.0) * 2.0 - 1.0
		var b := fmod(t * hertz * 1.008, 1.0) * 2.0 - 1.0
		low = lerpf(low, (a + b) * 0.5, 0.45)
		samples[index] += low * minf(t / 0.004, 1.0) * exp(-t * 5.5) * 0.4


## Normalise et marque la boucle. Les trois couches partagent ce chemin, donc
## le même gain relatif : elles se superposent sans qu'aucune n'écrase l'autre.
static func _loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	var gain := 0.86 / peak if peak > 0.0001 else 0.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	return stream
