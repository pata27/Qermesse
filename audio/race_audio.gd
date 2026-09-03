## Bande-son de la course — docs/04 §6.
##
## **Ne dépend que du contrôleur.** Aucun lien avec la scène 3D : le son doit
## continuer quand la fenêtre spectacle est fermée, et l'on doit pouvoir le
## tester sans rendu. Tout arrive par les signaux du contrôleur.
##
## **Un bus dédié.** Tous les sons passent par un bus `Course` créé au montage.
## La coupure globale est alors UNE opération, et elle ne touche pas au bus
## maître de la machine — couper le son de tout l'ordinateur depuis un logiciel
## de course serait une mauvaise surprise en soirée.
##
## **Silencieux par défaut**, voir `Settings.audio_muted`.
class_name RaceAudio
extends Node

const BUS_NAME := "Course"
## Enregistrements reels — `audio/CREDITS.md`. La synthese reste derriere
## chacun : un fichier absent est un son moins beau, jamais une soiree sans son.
const SAMPLES := {
	"cloche": "res://audio/samples/cloche.ogg",
	"clameur": "res://audio/samples/clameur.ogg",
	"reaction": "res://audio/samples/reaction.ogg",
}
## Vitesse à laquelle la nappe et le vent atteignent leur pleine intensité.
const FULL_SPEED_KPH := 55.0
## Accélération, en km/h par seconde, à partir de laquelle la foule réagit.
const CROWD_ACCEL_KPH_S := 9.0
## Distance de la ligne, en mètres, à laquelle la cloche sonne une fois.
const BELL_DISTANCE_M := 50.0
## Temps restant, en secondes, à partir duquel la cloche sonne en mode temps.
## Dix secondes : de quoi lancer un sprint final, sans sonner si tôt que
## l'annonce ne veuille plus rien dire.
const BELL_TIME_S := 10.0
## Repos entre deux clameurs : sans lui, une accélération soutenue déclencherait
## une réaction par image et la foule deviendrait un bourdonnement continu.
const CROWD_COOLDOWN_S := 2.5
## Repos entre deux souffles de depassement. Plus court que celui de la foule :
## un depassement est un fait de course, il se dit a chaque fois ou presque.
const WHOOSH_COOLDOWN_S := 0.8
## Avance minimale, en metres, pour qu'un changement de tete compte comme un
## depassement. Sous ce seuil, deux coureurs cote a cote echangent leurs places
## a chaque trame et la salle hurlerait sans discontinuer.
const OVERTAKE_MARGIN_M := 0.6
## Fenetre sur laquelle l'acceleration est mesuree. Voir `_on_progress` : sous
## une demi-seconde, on mesure la gigue du lissage et non le coureur.
const ACCEL_WINDOW_S := 0.5
## Attenuation du lit sonore pendant une annonce, en decibels, et le temps qu'il
## met a remonter. Sans elle, la cloche se noie dans le fond qu'elle interrompt.
const DUCK_DB := 11.0
const DUCK_RELEASE_S := 1.1

## Ce qui a sonné — pour les tests, qui tournent sans carte son, et pour la
## règle qui interdit d'en juger à l'oreille. `last_cue` donne le dernier son,
## `cue_counts` le nombre de fois que chacun a été déclenché depuis le début de
## la course. Sans ce témoin, six des sept sons ne pouvaient être vérifiés par
## rien : seul le faux départ l'écrivait.
var last_cue := ""
var cue_counts: Dictionary = {}

var _controller: AppController
var _bus := 0
var _drone: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rollers: AudioStreamPlayer
var _murmur: AudioStreamPlayer
var _whoosh: AudioStreamPlayer
var _knell: AudioStreamPlayer
var _roar: AudioStreamPlayer
## Les trois couches de la musique — remix vertical, voir `MusicForge`. Elles
## tournent ENSEMBLE du depart a l'arrivee ; seul leur volume change.
var _pulse: AudioStreamPlayer
var _drive: AudioStreamPlayer
var _lead: AudioStreamPlayer
## Musique du podium — majeur, plus lente, elle RESOUT. Voir `MusicForge`.
var _anthem: AudioStreamPlayer
var _beep: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _bell: AudioStreamPlayer
var _buzzer: AudioStreamPlayer
var _crowd: AudioStreamPlayer

var _running := false
var _bell_rung := false
var _crowd_rest_s := 0.0
var _whoosh_rest_s := 0.0
## Attenuation courante du lit, en decibels. Descend d'un coup, remonte doucement.
var _duck_db := 0.0
## Derniers instants de la course : la musique passe au complet.
var _final_push := false
var _last_speed_kph := 0.0
var _last_elapsed_s := 0.0
var _last_order: Array[int] = []
var _intensity := 0.0


func setup(controller: AppController) -> void:
	_controller = controller
	_bus = _ensure_bus()
	_build_players()
	set_muted(_controller.settings.audio_muted)
	set_volume_db(_controller.settings.audio_volume_db)

	_controller.countdown_tick.connect(_on_countdown)
	_controller.race_state_changed.connect(_on_race_state)
	_controller.progress_updated.connect(_on_progress)
	_controller.rider_finished.connect(_on_rider_finished)
	_controller.rider_eliminated.connect(_on_rider_eliminated)
	_controller.race_finished.connect(_on_race_finished)
	_controller.false_start_detected.connect(_on_false_start)


## Coupure globale — docs/04 §6 : « en événementiel, la sono est souvent gérée
## séparément et un logiciel qui sonne par-dessus la musique est un problème ».
func set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(_bus, muted)
	if _controller != null:
		_controller.settings.audio_muted = muted


func is_muted() -> bool:
	return AudioServer.is_bus_mute(_bus)


## Volume général de la bande-son, en décibels.
func set_volume_db(db: float) -> void:
	var level := clampf(db, -60.0, 6.0)
	AudioServer.set_bus_volume_db(_bus, level)
	# Symetrique de `set_muted` : le reglage suit le curseur, sinon le volume
	# ne vivrait que sur le bus et le lancement suivant repartirait a zero.
	if _controller != null:
		_controller.settings.audio_volume_db = level


func volume_db() -> float:
	return AudioServer.get_bus_volume_db(_bus)


## Effacement courant du lit, en decibels — pour les tests. C'est le MECANISME
## qu'on observe, pas le niveau d'un joueur : celui-ci depend aussi de
## l'intensite, et un test qui le lirait dirait deux choses a la fois.
## L'hymne du podium tourne-t-il ? Pour les tests : une fanfare de victoire qui
## survivrait a un abandon, ou qui couvrirait le decompte suivant, ne se voit
## dans aucune assertion sur les compteurs.
func podium_playing() -> bool:
	return _anthem.playing


func duck_db() -> float:
	return _duck_db


## Volume de chaque couche de musique, en decibels — pour les tests du remix
## vertical. `-60` vaut silence.
func music_levels() -> Dictionary:
	return {"pulse": _pulse.volume_db, "drive": _drive.volume_db, "lead": _lead.volume_db}


func _ensure_bus() -> int:
	var existing := AudioServer.get_bus_index(BUS_NAME)
	if existing >= 0:
		return existing
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, "Master")
	return index


func _build_players() -> void:
	# Les sons sont synthétisés UNE fois au montage. Les fabriquer à la volée
	# ferait un à-coup au premier bip, exactement comme les confettis.
	_drone = _make_player(SoundForge.drone(), -14.0)
	_wind = _make_player(SoundForge.wind(), -22.0)
	# LE LIT SONORE. C'est lui qui tient les vingt secondes ou il ne se passe
	# rien — docs/04 §6. Sans les rouleaux, la course n'avait aucun fond
	# audible : la nappe seule vit sous 200 Hz, la ou un haut-parleur
	# d'ordinateur ne restitue rien.
	_rollers = _make_player(SoundForge.rollers(), -20.0)
	_murmur = _make_player(SoundForge.crowd_bed(), -24.0)
	_whoosh = _make_player(SoundForge.whoosh(), -10.0)
	_knell = _make_player(SoundForge.knell(), -8.0)
	_roar = _make_player(_sampled("clameur", SoundForge.roar()), -2.0)
	_pulse = _make_player(MusicForge.pulse(), -12.0)
	_drive = _make_player(MusicForge.drive(), -60.0)
	_lead = _make_player(MusicForge.lead(), -60.0)
	_anthem = _make_player(MusicForge.anthem(), -14.0)
	_beep = _make_player(SoundForge.beep(), -6.0)
	_horn = _make_player(SoundForge.horn(), -4.0)
	# CES TROIS-LA SONT DES ENREGISTREMENTS. Une foule est faite de centaines de
	# voix correlees, une cloche est une geometrie de bronze : approchees en
	# code elles s'entendaient comme du bruit blanc et comme des bips. C'est la
	# limite de l'exercice, pas un defaut d'implementation — docs/04 §6.
	_bell = _make_player(_sampled("cloche", SoundForge.bell()), -5.0)
	# Le buzzer du faux départ est le klaxon, une octave sous le départ : le
	# même timbre dit « ligne de départ », la hauteur dit « pas comme ça ».
	_buzzer = _make_player(SoundForge.horn(0.5), -4.0)
	_buzzer.pitch_scale = 0.5
	_crowd = _make_player(_sampled("reaction", SoundForge.crowd()), -9.0)


## L'enregistrement s'il est la, la synthese sinon.
##
## LE REPLI N'EST PAS DECORATIF. Un export mal ficele, un fichier corrompu, une
## plateforme qui n'importe pas le Vorbis — et l'ecran public passerait une
## soiree entiere muet sur ses trois sons les plus attendus. Un son moins beau
## vaut infiniment mieux que pas de son.
static func sampled_or(path: String, fallback: AudioStream) -> AudioStream:
	if not ResourceLoader.exists(path):
		return fallback
	var stream := ResourceLoader.load(path) as AudioStream
	return fallback if stream == null else stream


static func _sampled(key: String, fallback: AudioStream) -> AudioStream:
	return sampled_or(str(SAMPLES[key]), fallback)


func _make_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = db
	player.bus = BUS_NAME
	add_child(player)
	return player


func _on_countdown(value: int) -> void:
	if value > 0:
		# Le bip monte d'un demi-ton à chaque seconde : l'oreille sait alors où
		# elle en est sans compter.
		_beep.pitch_scale = 1.0 + (3 - value) * 0.06
		_beep.play()
		_cue("bip")
	else:
		_duck()
		_horn.play()
		_cue("klaxon")


## docs/02 §4, AVERTISSEMENT : « bandeau + son ». `IGNORE`, lui, est « loggué
## uniquement » — ni bandeau ni son.
func _on_false_start(_rider: int, policy: int) -> void:
	if policy == RaceConfig.FalseStartPolicy.IGNORE:
		return
	_buzzer.play()
	_cue("faux-depart")


func _on_race_state(_previous: int, current: int) -> void:
	# LE COMPTE REPART A L'ARMEMENT, pas au depart. Les bips du decompte et le
	# klaxon sonnent AVANT que la course ne coure : remis a zero a l'entree en
	# course, ils etaient effaces juste apres avoir sonne, et le temoin affirmait
	# qu'ils n'avaient jamais retenti.
	if current == RaceEngine.State.ARMING:
		cue_counts.clear()
	# LE PODIUM S'EFFACE DEVANT LA COURSE SUIVANTE. L'hymne tourne tant que le
	# classement est a l'ecran — parfois une minute — et il doit se taire au
	# premier decompte. IDLE compte aussi : une course ABANDONNEE n'a pas de
	# podium, et une fanfare de victoire sur un abandon serait grotesque.
	if current == RaceEngine.State.ARMING or current == RaceEngine.State.IDLE:
		_anthem.stop()
	var now_running := current == RaceEngine.State.RUNNING
	if now_running == _running:
		return
	_running = now_running
	if _running:
		_bell_rung = false
		_last_order.clear()
		_intensity = 0.0
		_duck_db = 0.0
		_final_push = false
		_drone.play()
		_wind.play()
		_rollers.play()
		_murmur.play()
		# LES TROIS COUCHES PARTENT ENSEMBLE, sur la meme image. Les lancer au
		# fil de l'intensite les aurait desynchronisees : chacune reprendrait sa
		# boucle a un endroit different, et deux mesures plus tard la batterie
		# ne tomberait plus sur la basse.
		_pulse.play()
		_drive.play()
		_lead.play()
		_cue("musique")
	else:
		_drone.stop()
		_wind.stop()
		_rollers.stop()
		_murmur.stop()
		_pulse.stop()
		_drive.stop()
		_lead.stop()


func _process(delta: float) -> void:
	_crowd_rest_s = maxf(0.0, _crowd_rest_s - delta)
	_whoosh_rest_s = maxf(0.0, _whoosh_rest_s - delta)
	# Le lit remonte doucement apres une annonce ; il a plonge d'un coup.
	_duck_db = maxf(0.0, _duck_db - delta * DUCK_DB / DUCK_RELEASE_S)
	if not _running:
		return
	# La montée est amortie : indexer directement le volume sur une vitesse
	# mesurée au tick ferait pomper la nappe au rythme du capteur.
	_drone.volume_db = -26.0 + _intensity * 12.0 - _duck_db
	_wind.volume_db = -36.0 + _intensity * 14.0 - _duck_db
	_wind.pitch_scale = 0.75 + _intensity * 0.7
	# LES ROULEAUX PORTENT LA COURSE. Ils existent des le depart — une salle
	# de goldsprint gronde avant meme que la vitesse ne monte — et leur hauteur
	# suit la vitesse, comme un vrai rouleau.
	_rollers.volume_db = -22.0 + _intensity * 16.0 - _duck_db
	_rollers.pitch_scale = 0.72 + _intensity * 0.55
	_murmur.volume_db = -22.0 + _intensity * 9.0 - _duck_db

	# REMIX VERTICAL — docs/04 §6. La pulsation est la du depart a l'arrivee ;
	# la batterie monte avec l'allure ; le theme n'entre que dans les derniers
	# instants, ou quand la course s'emballe vraiment. La musique raconte donc
	# la course sans jamais couper.
	var push := 1.0 if _final_push else 0.0
	_pulse.volume_db = -13.0 + _intensity * 5.0 + push * 2.0
	_drive.volume_db = _layer_db(_intensity, 0.30, push)
	_lead.volume_db = _layer_db(_intensity, 0.62, push)


func _on_progress(state: RaceState) -> void:
	if not _running:
		return
	var leader := -1
	var trailer := -1
	var order: Array[int] = []
	for rider: int in state.config.active_riders:
		order.append(rider)
		if leader < 0 or state.distance_m[rider] > state.distance_m[leader]:
			leader = rider
		if trailer < 0 or state.distance_m[rider] < state.distance_m[trailer]:
			trailer = rider
	if leader < 0:
		return

	# En poursuite, c'est l'ÉCART qui porte la tension, pas la vitesse : c'est
	# le sujet du mode, la nappe doit dire la même chose que l'image.
	var speed := state.display_speed_kph[leader]
	if state.config.mode == RaceConfig.Mode.PURSUIT and trailer >= 0:
		var gap: float = state.distance_m[leader] - state.distance_m[trailer]
		_intensity = clampf(gap / maxf(1.0, state.config.gap_m), 0.0, 1.0)
	else:
		_intensity = clampf(speed / FULL_SPEED_KPH, 0.0, 1.0)

	# L'ACCELERATION SE MESURE SUR UNE DEMI-SECONDE, pas d'une trame a l'autre.
	#
	# Les trames arrivent a 20 Hz : sur cinq centiemes de seconde, un demi-km/h
	# de gigue du lissage donne dix km/h par seconde — le seuil exact de la
	# clameur. La salle reagissait donc au BRUIT DE MESURE, une fois toutes les
	# deux secondes et demie du depart a l'arrivee, et une salle qui hurle sans
	# discontinuer ne hurle plus.
	var elapsed := float(state.elapsed_ms) / 1000.0
	var window := elapsed - _last_elapsed_s
	if elapsed > 0.5 and window >= ACCEL_WINDOW_S:
		if (speed - _last_speed_kph) / window > CROWD_ACCEL_KPH_S:
			_cheer()
		_last_speed_kph = speed
		_last_elapsed_s = elapsed

	# Dépassement : l'ordre au classement a changé. C'est le moment où une salle
	# réagit vraiment, bien plus qu'à une accélération.
	order.sort_custom(func(a: int, b: int) -> bool:
		return state.distance_m[a] > state.distance_m[b])
	if not _last_order.is_empty() and order != _last_order and _real_overtake(state, order):
		# DEUX SONS POUR DEUX INFORMATIONS. La clameur dit que la salle a
		# reagi ; le souffle dit ce qui s'est passe sur la piste. L'un sans
		# l'autre laisse le public deviner lequel des deux vient d'arriver.
		if _whoosh_rest_s <= 0.0:
			_whoosh_rest_s = WHOOSH_COOLDOWN_S
			_whoosh.pitch_scale = randf_range(0.9, 1.15)
			_whoosh.play()
			_cue("souffle")
		_cheer()
	_last_order = order

	# Cloche de la fin imminente — une seule fois, docs/04 §6.
	#
	# Un goldsprint n'a pas de tour, et une course en TEMPS n'a pas de mètres :
	# la cloche n'y sonnait donc jamais, et le public n'avait aucune annonce de
	# la fin alors qu'en distance il en avait une. C'est le même événement, il
	# se dit dans les deux modes. La poursuite se tait : sa fin arrive quand
	# l'écart se referme, ce que rien ne permet d'annoncer à l'avance.
	if not _bell_rung and _final_stretch(state, leader):
		_bell_rung = true
		# DERNIERS INSTANTS : tout monte. C'est le moment que la salle attend.
		_final_push = true
		_duck()
		_bell.play()
		_cue("cloche")


## La course entre-t-elle dans ses derniers instants ?
##
## LE SEUIL NE PEUT PAS DEPASSER LE DERNIER QUART DE L'EPREUVE. Cinquante
## metres est le bon repere sur cinq cents ; sur une course de cinquante — la
## distance MINIMALE que la configuration accepte —, la cloche sonnait sur la
## ligne de depart. Meme piege en temps : dix secondes d'annonce sur une course
## de dix secondes. Une annonce de fin qui tombe au depart ne dit plus rien.
static func _final_stretch(state: RaceState, leader: int) -> bool:
	match state.config.mode:
		RaceConfig.Mode.DISTANCE:
			var margin := minf(BELL_DISTANCE_M, state.config.distance_m * 0.25)
			return state.config.distance_m - state.distance_m[leader] <= margin
		RaceConfig.Mode.TIME:
			var left := state.config.duration_s - float(state.elapsed_ms) / 1000.0
			return left <= minf(BELL_TIME_S, state.config.duration_s * 0.25)
	return false


## Glas d'elimination — docs/04 §6. Une elimination est le contraire d'une
## clameur : c'est quelqu'un qui sort, et la salle le sait avant de l'avoir lu.
func _on_rider_eliminated(_rider: int, _rank: int, _gap_m: float) -> void:
	_duck()
	_knell.play()
	_cue("glas")


## Fait plonger le lit sonore le temps d'une annonce.
func _duck() -> void:
	_duck_db = DUCK_DB


func _on_rider_finished(_rider: int, _elapsed_ms: int, _rank: int) -> void:
	_cheer(true)


## Volume d'une couche de musique : muette sous son seuil, puis montant jusqu'a
## son plein niveau. `-60 dB` vaut silence — la couche continue de tourner, ce
## qui la garde en phase avec les autres.
static func _layer_db(intensity: float, threshold: float, push: float) -> float:
	var reach := clampf((intensity - threshold) / 0.25, 0.0, 1.0)
	reach = maxf(reach, push)
	return -60.0 if reach <= 0.0 else lerpf(-24.0, -11.0, reach)


## L'ARRIVEE EST LE MOMENT DE LA SOIREE. Une clameur d'une seconde et demie n'y
## suffit pas : la salle hurle, et ça s'entend comme tel. Le lit plonge dessous
## — il n'a plus rien a dire, la course est finie.
func _on_race_finished(_result: RaceResult) -> void:
	_duck()
	_roar.play()
	_cue("clameur")
	# L'HYMNE ENTRE SOUS LA CLAMEUR, pas apres. La salle hurle, et la musique
	# monte dessous : c'est ce qui transforme un resultat en ceremonie. Attendre
	# la fin de la clameur aurait laisse un trou de quatre secondes a l'instant
	# ou le podium s'affiche.
	_anthem.play()
	_cue("podium")


## Le changement d'ordre est-il un VRAI depassement ?
##
## Deux coureurs a dix centimetres l'un de l'autre echangent leurs places a
## chaque trame : au profil « egaux », la course produisait ainsi une clameur
## toutes les deux secondes et demie, du depart a l'arrivee. Une salle qui
## hurle en continu ne hurle plus — et l'ecoute a ete sans appel.
##
## Un depassement se constate quand le nouveau premier a PRIS DU CHAMP sur
## celui qu'il vient de passer. En deca, c'est du bruit de mesure, pas un fait
## de course.
static func _real_overtake(state: RaceState, order: Array[int]) -> bool:
	if order.size() < 2:
		return false
	var gap: float = state.distance_m[order[0]] - state.distance_m[order[1]]
	return gap >= OVERTAKE_MARGIN_M


## Clameur. `insistent` ignore le repos : un franchissement mérite toujours sa
## réaction, même s'il suit de près un dépassement.
func _cheer(insistent: bool = false) -> void:
	if not insistent and _crowd_rest_s > 0.0:
		return
	_crowd_rest_s = CROWD_COOLDOWN_S
	_crowd.pitch_scale = randf_range(0.94, 1.06)
	_crowd.play()
	_cue("foule")


## Note ce qui vient de sonner. Le rendu audio lui-même n'est pas observable
## depuis un test ; ce compteur l'est.
func _cue(name: String) -> void:
	last_cue = name
	cue_counts[name] = int(cue_counts.get(name, 0)) + 1
