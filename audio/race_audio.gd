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
## Vitesse à laquelle la nappe et le vent atteignent leur pleine intensité.
const FULL_SPEED_KPH := 55.0
## Accélération, en km/h par seconde, à partir de laquelle la foule réagit.
const CROWD_ACCEL_KPH_S := 9.0
## Distance de la ligne, en mètres, à laquelle la cloche sonne une fois.
const BELL_DISTANCE_M := 50.0
## Repos entre deux clameurs : sans lui, une accélération soutenue déclencherait
## une réaction par image et la foule deviendrait un bourdonnement continu.
const CROWD_COOLDOWN_S := 2.5

var _controller: AppController
var _bus := 0
var _drone: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _beep: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _bell: AudioStreamPlayer
var _buzzer: AudioStreamPlayer
## Dernier son déclenché — pour les tests, qui tournent sans carte son.
var last_cue := ""
var _crowd: AudioStreamPlayer

var _running := false
var _bell_rung := false
var _crowd_rest_s := 0.0
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
	_beep = _make_player(SoundForge.beep(), -6.0)
	_horn = _make_player(SoundForge.horn(), -4.0)
	_bell = _make_player(SoundForge.bell(), -7.0)
	# Le buzzer du faux départ est le klaxon, une octave sous le départ : le
	# même timbre dit « ligne de départ », la hauteur dit « pas comme ça ».
	_buzzer = _make_player(SoundForge.horn(0.5), -4.0)
	_buzzer.pitch_scale = 0.5
	_crowd = _make_player(SoundForge.crowd(), -9.0)


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
	else:
		_horn.play()


## docs/02 §4, AVERTISSEMENT : « bandeau + son ». `IGNORE`, lui, est « loggué
## uniquement » — ni bandeau ni son.
func _on_false_start(_rider: int, policy: int) -> void:
	if policy == RaceConfig.FalseStartPolicy.IGNORE:
		return
	_buzzer.play()
	last_cue = "faux-depart"


func _on_race_state(_previous: int, current: int) -> void:
	var now_running := current == RaceEngine.State.RUNNING
	if now_running == _running:
		return
	_running = now_running
	if _running:
		_bell_rung = false
		_last_order.clear()
		_intensity = 0.0
		_drone.play()
		_wind.play()
	else:
		_drone.stop()
		_wind.stop()


func _process(delta: float) -> void:
	_crowd_rest_s = maxf(0.0, _crowd_rest_s - delta)
	if not _running:
		return
	# La montée est amortie : indexer directement le volume sur une vitesse
	# mesurée au tick ferait pomper la nappe au rythme du capteur.
	_drone.volume_db = -30.0 + _intensity * 16.0
	_wind.volume_db = -34.0 + _intensity * 18.0
	_wind.pitch_scale = 0.75 + _intensity * 0.7


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

	var elapsed := float(state.elapsed_ms) / 1000.0
	if elapsed > 0.5:
		var accel := (speed - _last_speed_kph) / maxf(elapsed - _last_elapsed_s, 0.001)
		if accel > CROWD_ACCEL_KPH_S:
			_cheer()
	_last_speed_kph = speed
	_last_elapsed_s = elapsed

	# Dépassement : l'ordre au classement a changé. C'est le moment où une salle
	# réagit vraiment, bien plus qu'à une accélération.
	order.sort_custom(func(a: int, b: int) -> bool:
		return state.distance_m[a] > state.distance_m[b])
	if not _last_order.is_empty() and order != _last_order:
		_cheer()
	_last_order = order

	# Cloche des derniers mètres — une seule fois, en mode distance.
	if not _bell_rung and state.config.mode == RaceConfig.Mode.DISTANCE:
		if state.config.distance_m - state.distance_m[leader] <= BELL_DISTANCE_M:
			_bell_rung = true
			_bell.play()


func _on_rider_finished(_rider: int, _elapsed_ms: int, _rank: int) -> void:
	_cheer(true)


func _on_race_finished(_result: RaceResult) -> void:
	_cheer(true)


## Clameur. `insistent` ignore le repos : un franchissement mérite toujours sa
## réaction, même s'il suit de près un dépassement.
func _cheer(insistent: bool = false) -> void:
	if not insistent and _crowd_rest_s > 0.0:
		return
	_crowd_rest_s = CROWD_COOLDOWN_S
	_crowd.pitch_scale = randf_range(0.94, 1.06)
	_crowd.play()
