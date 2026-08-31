## Simulateur de lien, en GDScript pur — docs/03 §5 et docs/07 §8.
##
## Il produit EXACTEMENT les memes trames que le firmware, bugs compris. Il ne
## traverse pas le port serie : c'est ce qui le rend gratuit en CI et disponible
## sur les trois OS, et c'est aussi ce qu'il ne teste pas. Pour eprouver la
## couche serie elle-meme, c'est `tools/ss_emu` qu'il faut, sur pseudo-terminal.
##
## Deterministe a graine fixee : un scenario se rejoue a l'identique.
extends Node

signal frame_received(kind: int, payload: Dictionary)
signal state_changed(state: int)

## Pas de simulation fixe : le comportement ne doit pas dependre du framerate.
const STEP_S := 0.001
const UPDATE_INTERVAL_MS := 10  ## throttle firmware, docs/01 §1
const FALSE_START_TICKS := 4

## Profils de docs/07 §5, en km/h de croisiere par piste.
const PROFILES := {
	"egaux": [45.0, 44.92, 45.06, 44.97],
	"ecart-leger": [45.0, 47.25, 44.6, 45.3],
	"domination": [40.0, 55.0, 41.5, 39.0],
	"remontee-finale": [48.0, 43.0, 44.0, 43.5],
	"abandon": [45.0, 46.0, 44.0, 45.5],
}

@export var wired_riders: int = 2  ## le boitier de l'utilisateur : 2 capteurs
@export var profile: String = "egaux"
@export var roller_mm: float = Protocol.DEFAULT_ROLLER_MM
@export var seed: int = 42
@export var identify_delay_s: float = 0.15  ## on ne s'identifie pas instantanement
## Acceleration du temps simule. Sert aux demonstrations — une course de 60 s
## se montre en 6 s — et aux tests, qui derouleraient sinon une course entiere
## en temps reel. Sans effet sur le materiel : le firmware a sa propre horloge.
@export var time_scale: float = 1.0

var _state: int = Protocol.State.DISCONNECTED
var _running := false
var _elapsed_s := 0.0
var _accumulator := 0.0

var _connect_at_s := 0.0
var _race_starting := false
var _race_started := false
var _race_type_distance := true
var _race_length_ticks := 20
var _last_countdown := 0
var _countdown_at_s := 0.0
var _race_start_s := 0.0
var _last_update_ms := 0

var _ticks := [0, 0, 0, 0]
var _finish_ms := [0, 0, 0, 0]
var _distance_mm := [0.0, 0.0, 0.0, 0.0]
var _false_start_emitted := [false, false, false, false]

var _pending_false_start := []
var _pending_faults := []
var _last_error := ""


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _running:
		return
	advance(delta * time_scale)


## Point d'entree deterministe, utilise tel quel par les tests headless.
func advance(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= STEP_S:
		_accumulator -= STEP_S
		_step()


func _step() -> void:
	_elapsed_s += STEP_S

	if _state == Protocol.State.PORT_OPEN and _elapsed_s >= _connect_at_s:
		_emit(Protocol.Frame.VERSION, {"text": Protocol.FIRMWARE_VERSION, "truncated": false})
		_set_state(Protocol.State.IDENTIFIED)

	if _race_starting:
		_step_countdown()
	if _race_started:
		_step_race()


func _step_countdown() -> void:
	# docs/01 §2 : le premier CD: n'arrive qu'APRES 1000 ms.
	if _elapsed_s - _countdown_at_s > 1.0:
		_last_countdown -= 1
		_countdown_at_s = _elapsed_s
		_emit(Protocol.Frame.COUNTDOWN, {"value": _last_countdown})

	# Faux depart : >= 4 fronts pendant le decompte.
	for rider: int in _pending_false_start:
		if not _false_start_emitted[rider]:
			_false_start_emitted[rider] = true
			_emit(Protocol.Frame.FALSE_START, {"rider": rider})

	if _last_countdown == 0:
		_start_race()


func _start_race() -> void:
	_race_starting = false
	_race_started = true
	_race_start_s = _elapsed_s
	_last_update_ms = 0
	for i: int in range(Protocol.MAX_RIDERS):
		_ticks[i] = 0
		_finish_ms[i] = 0
		_distance_mm[i] = 0.0


func _step_race() -> void:
	var race_s := _elapsed_s - _race_start_s
	var elapsed_ms := int(race_s * 1000.0)
	var circumference := Protocol.circumference_mm(roller_mm)

	for i: int in range(wired_riders):
		var kph := _speed_kph(i, race_s)
		_distance_mm[i] += kph * 0.2777777777777778 * (STEP_S * 1000.0)
		var target := int(floor(_distance_mm[i] / circumference))
		if target > _ticks[i]:
			_ticks[i] = target

	if _race_type_distance:
		_check_distance(elapsed_ms)
	# Mode temps : avec t60, le firmware ne termine JAMAIS de lui-meme
	# (docs/01 §5.5). Le simulateur reproduit ce silence, volontairement.

	if elapsed_ms - _last_update_ms > UPDATE_INTERVAL_MS:
		_last_update_ms = elapsed_ms
		_emit(
			Protocol.Frame.PROGRESS,
			{"ticks": _ticks.duplicate(), "elapsed_ms": elapsed_ms}
		)


func _check_distance(elapsed_ms: int) -> void:
	var all_finished := true
	for i: int in range(Protocol.MAX_RIDERS):
		if _finish_ms[i] == 0 and _ticks[i] >= _race_length_ticks:
			_finish_ms[i] = elapsed_ms
			_emit(Protocol.Frame.RIDER_FINISH, {"rider": i, "elapsed_ms": elapsed_ms})
		if _finish_ms[i] == 0:
			all_finished = false
	# LE bug de la v1 : le firmware attend les QUATRE pistes materielles. Avec
	# 2 capteurs cables, cette condition n'est jamais vraie et la course ne se
	# termine jamais (docs/01 §5.1). Reproduit a dessein.
	if all_finished:
		_race_started = false


func _speed_kph(rider: int, race_s: float) -> float:
	if rider >= wired_riders:
		return 0.0
	var speeds: Array = PROFILES.get(profile, PROFILES["egaux"])
	var cruise: float = speeds[rider]
	if profile == "abandon" and rider == 1 and race_s >= 20.0:
		return 0.0
	var v: float = min(cruise, 22.0 * race_s)  # montee en regime
	if profile == "remontee-finale":
		if rider == 0:
			v -= 6.0 * (race_s / 60.0)  # fatigue
		elif rider == 1 and race_s >= 25.0:
			v += 12.0
	# Gigue deterministe : somme de sinusoides, pas de generateur aleatoire, donc
	# aucun etat a resynchroniser entre deux rejeux.
	var phase := float(seed % 1000) * 0.017 + float(rider) * 1.7
	var noise := (
		0.6 * sin(race_s * 2.3 + phase)
		+ 0.3 * sin(race_s * 7.1 + phase * 1.9)
		+ 0.1 * sin(race_s * 17.3 + phase * 0.4)
	)
	v += v * 0.015 * noise
	return maxf(0.0, v)


func _emit(kind: int, payload: Dictionary) -> void:
	frame_received.emit(kind, payload)


func _set_state(state: int) -> void:
	if _state == state:
		return
	_state = state
	state_changed.emit(state)


# --- Interface commune, identique a link_serial.gd ---------------------------

func list_ports() -> Array:
	return [
		{
			"port": "SIMULATEUR",
			"description": "profil %s, %d capteurs cables" % [profile, wired_riders],
			"vid": -1,
			"pid": -1,
			"known_device": false,
			"candidate": true,
			"reason": "simulateur integre",
		}
	]


func set_preferred_port(_port: String) -> void:
	pass


func start() -> void:
	_running = true
	_connect_at_s = _elapsed_s + identify_delay_s
	_set_state(Protocol.State.PORT_OPEN)


func stop() -> void:
	_running = false
	_race_starting = false
	_race_started = false
	_set_state(Protocol.State.DISCONNECTED)


## Meme validation que le driver natif — docs/01 §2 et §5.5. Un simulateur plus
## permissif que le materiel laisserait passer des bugs jusqu'au terrain.
func send_command(cmd: String) -> bool:
	_last_error = ""
	if cmd.is_empty():
		_last_error = "commande vide"
		return false
	if cmd.length() == 1:
		return _apply_simple_command(cmd)
	return _apply_argument_command(cmd)


func _apply_simple_command(cmd: String) -> bool:
	match cmd:
		"v":
			_emit(
				Protocol.Frame.VERSION,
				{"text": Protocol.FIRMWARE_VERSION, "truncated": false}
			)
		"s":
			_race_starting = false
			_race_started = false
		"g":
			_arm_countdown()
		"d":
			_race_type_distance = true
		"x":
			_race_type_distance = false
		"m":
			_emit(Protocol.Frame.MOCK_ACK, {"on": true})
		_:
			_last_error = "commande inconnue : '%s' (docs/01 §2)" % cmd
			return false
	return true


func _apply_argument_command(cmd: String) -> bool:
	var problem := _argument_problem(cmd)
	if not problem.is_empty():
		_last_error = problem
		return false
	if cmd[0] == "l":
		_race_length_ticks = cmd.substr(1).to_int()
		_emit(Protocol.Frame.LENGTH_ACK, {"ticks": _race_length_ticks})
	return true


## Rend une chaine vide si la commande est acceptable, sinon le motif du refus.
func _argument_problem(cmd: String) -> String:
	var head := cmd[0]
	if head != "l" and head != "t":
		return "seules 'l' et 't' prennent un argument (docs/01 §2)"
	var arg := cmd.substr(1)
	if not arg.is_valid_int():
		return "argument non numerique : %s" % cmd
	# Contrainte 1 : charBuff[8] du firmware, sans garde de depassement.
	if arg.length() > 7:
		return "argument de %d chiffres, le firmware en accepte 7" % arg.length()
	# Contrainte 2 : atoi remplit un int 16 bits.
	var value := arg.to_int()
	if value < 1 or value > 32767:
		return "valeur %d hors plage 1..32767 (int 16 bits)" % value
	# Contrainte 3 : une duree qui ne deborde pas en negatif ferait terminer le
	# firmware et couperait le flux R: en pleine course.
	if head == "t" and _avr_mul_1000(value) >= 0:
		return (
			"t%d terminerait le firmware a %d ms : utiliser %s (docs/01 §5.5)"
			% [value, _avr_mul_1000(value), Protocol.TIME_COMMAND]
		)
	return ""


## Arithmetique de l'ATmega328P : `int` = 16 bits signes.
func _avr_mul_1000(secs: int) -> int:
	var wrapped := (secs * 1000) & 0xFFFF
	return wrapped - 65536 if wrapped >= 32768 else wrapped


func _arm_countdown() -> void:
	_race_starting = true
	_race_started = false
	_last_countdown = 4
	_countdown_at_s = _elapsed_s
	for i: int in range(Protocol.MAX_RIDERS):
		_ticks[i] = 0
		_finish_ms[i] = 0
		_distance_mm[i] = 0.0
		_false_start_emitted[i] = false


func get_last_error() -> String:
	return _last_error


func get_firmware_version() -> String:
	return Protocol.FIRMWARE_VERSION if _state == Protocol.State.IDENTIFIED else ""


func get_link_state() -> int:
	return _state


func can_start_race() -> bool:
	return _state == Protocol.State.IDENTIFIED


func set_race_active(_active: bool) -> void:
	pass  # pas de watchdog a simuler : le simulateur ne perd jamais le lien


func set_simulation_speed(scale: float) -> void:
	time_scale = maxf(0.01, scale)


## Nombre de capteurs « cablés » du boîtier simulé. Les pistes au-delà restent à
## HIGH, comme un connecteur vide.
func set_wired_riders(count: int) -> void:
	wired_riders = clampi(count, 1, Protocol.MAX_RIDERS)


func get_stats() -> Dictionary:
	return {
		"frames_total": 0,
		"frames_progress": 0,
		"frames_unknown": 0,
		"frames_dropped": 0,
		"lines_overlong": 0,
		"connects": 1 if _state == Protocol.State.IDENTIFIED else 0,
		"handshake_failures": 0,
		"watchdog_trips": 0,
		"races_interrupted": 0,
		"simulated": true,
	}


# --- Injection de pannes, miroir de docs/07 §6 -------------------------------

## Le rider pedale pendant le decompte : produit FS:<i>.
func inject_false_start(rider: int) -> void:
	if rider >= 0 and rider < Protocol.MAX_RIDERS and not _pending_false_start.has(rider):
		_pending_false_start.append(rider)


## Rebond de contact : un tick de plus, sans mouvement (docs/01 §6.3).
func inject_phantom_tick(rider: int) -> void:
	if rider >= 0 and rider < Protocol.MAX_RIDERS:
		_ticks[rider] += 1
		_distance_mm[rider] += Protocol.circumference_mm(roller_mm)


## Trame corrompue : exactement celle que produit `ss_emu --inject trame-corrompue`.
func inject_corrupt_frame() -> void:
	_emit(Protocol.Frame.UNKNOWN, {"text": "R:\\x01\\x99\\xC3 42,,", "truncated": false})


## Coupure du lien : le simulateur cesse d'emettre, comme un cable arrache.
func inject_link_loss() -> void:
	_set_state(Protocol.State.LINK_LOST)
	_running = false


func inject_link_return() -> void:
	_running = true
	_set_state(Protocol.State.IDENTIFIED)
