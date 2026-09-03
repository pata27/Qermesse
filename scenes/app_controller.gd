## Assemblage de l'application — le seul endroit qui connaisse a la fois le lien
## materiel et le coeur metier.
##
## `core/` ne depend de rien et `hardware/` ne connait pas les regles de course :
## il faut donc bien un point ou les deux se rencontrent. C'est ici, et nulle
## part ailleurs.
##
## L'interface n'appelle QUE des methodes de ce controleur ; elle ne mute jamais
## l'etat directement (docs/03 §1, « vue vers commande : une vue ne mute jamais
## l'etat, elle emet une intention »). C'est aussi ce qui rend le jalon J3
## demontrable en headless : les tests appellent exactement ce que les boutons
## appellent.
class_name AppController
extends Node

signal link_state_changed(state: int)
signal race_state_changed(previous: int, current: int)
signal countdown_tick(value: int)
signal progress_updated(state: RaceState)
signal rider_finished(rider: int, elapsed_ms: int, rank: int)
signal rider_eliminated(rider: int, rank: int, gap_m: float)
signal false_start_detected(rider: int, policy: int)
signal race_finished(result: RaceResult)
signal race_aborted(note: String)
signal notice(text: String)
## Ticks bruts par piste, pour le test capteurs du panneau materiel.
signal sensor_activity(ticks: PackedInt32Array)

## docs/01 §6.2 — au-dela, la course est perdue.
const LINK_GRACE_MS := 3000
## Au-dela de ce temps de course sans un seul tick, une piste cochee est
## signalee. Dix secondes : assez pour qu'un depart lent ne declenche rien,
## assez tot pour arreter et repartir avant que le public ne s'impatiente.
##
## C'est le bug de la v1 sous une autre forme. En distance le PC attend TOUTES
## les pistes actives : une piste cochee sans coureur — ou dont le capteur est
## debranche — les fait attendre jusqu'au plafond de dix minutes. `DEPANNAGE`
## demandait a l'operateur de le verifier lui-meme ; le logiciel le voit.
const SILENT_LANE_MS := 10000

## Coutures de test, a fixer AVANT l'entree dans l'arbre. En production elles
## gardent leurs valeurs par defaut ; en test elles evitent d'ecrire dans les
## donnees de l'utilisateur et de dependre de ses reglages.
var preferences_enabled := true
## Coutures de test : fichiers de reglages et de roster. Vides = chemins de
## l'utilisateur.
var settings_path := ""
var roster_path := ""
var recorder_logs_dir := ""
var recorder_races_dir := ""

var settings := Settings.new()
var roster := Roster.new()
var engine := RaceEngine.new()
var recorder: Recorder = null

## Ce qui a mal tourne au chargement des fichiers de l'utilisateur. Un fichier
## illisible remet tout a zero SANS empecher le demarrage — mais pas en
## silence : le panneau course le dit. « Bruyamment », comme promis.
var _startup_problems: Array[String] = []
## Pistes deja signalees comme muettes, pour ne le dire qu'une fois par course.
var _silent_lanes_warned: Array[int] = []
var _dropped_warned := false
var _link: Link = null
var _link_lost_since_ms: int = -1
var _rejected_ticks: int = 0
var _last_rejection: String = ""
var _last_link_state: int = Protocol.State.DISCONNECTED
var _history: Array[RaceResult] = []
var _sensor_test_active := false
var _sensor_baseline := PackedInt32Array()


var _initialized := false


func _ready() -> void:
	initialize()


## Construit le lien, le recorder et le cablage des signaux. IDEMPOTENTE, et
## appelable avant l'entree dans l'arbre.
##
## Godot ne declenche ni `_enter_tree` ni `_ready` de facon synchrone quand on
## ajoute un noeud depuis `SceneTree._initialize()` : un outil en ligne de
## commande qui construisait l'interface juste apres `add_child` la batissait
## donc contre un controleur vide, et le panneau materiel affichait « aucun
## port » sans rien signaler. Une initialisation explicite supprime toute la
## classe de bugs d'ordonnancement, plutot que de la contourner au cas par cas.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true

	if preferences_enabled:
		_load_user_file(settings.load_from.bind(settings_path), "REGLAGES")
		_load_user_file(roster.load_from.bind(roster_path), "ROSTER")

	_link = Link.new()
	_link.name = "Link"
	add_child(_link)
	_link.frame_received.connect(_on_frame)
	_link.state_changed.connect(_on_link_state)

	# UN SEUL SENS POUR `preferences_enabled` : ce controleur ne touche a AUCUNE
	# donnee de l'utilisateur. Il protegeait les reglages et le roster, mais le
	# recorder continuait de viser les dossiers de l'operateur — les demos lui
	# ont ainsi depose des dizaines de courses dans « Courses du jour ». Un
	# dossier explicite reste prioritaire : outils et tests visent ou ils
	# veulent.
	if not preferences_enabled:
		var aside := ProjectSettings.globalize_path("user://sans-donnees")
		if recorder_logs_dir.is_empty():
			recorder_logs_dir = aside.path_join("logs")
		if recorder_races_dir.is_empty():
			recorder_races_dir = aside.path_join("races")
	recorder = Recorder.new(recorder_logs_dir, recorder_races_dir)
	# Un redemarrage en pleine soiree ne vide pas « Courses du jour ».
	_history = recorder.load_day()

	engine.command_requested.connect(_on_command_requested)
	engine.state_changed.connect(func(p: int, c: int) -> void: race_state_changed.emit(p, c))
	engine.countdown_tick.connect(func(v: int) -> void: countdown_tick.emit(v))
	engine.progress_updated.connect(_on_progress_updated)
	engine.rider_finished.connect(_on_rider_finished)
	engine.rider_eliminated.connect(_on_rider_eliminated)
	engine.false_start_detected.connect(_on_false_start)
	engine.race_finished.connect(_on_race_finished)
	engine.race_aborted.connect(_on_race_aborted)
	engine.tick_rejected.connect(_on_tick_rejected)
	engine.speed_implausible.connect(_on_speed_implausible)

	_sensor_baseline.resize(Protocol.MAX_RIDERS)
	apply_backend(settings.use_simulator)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	engine.tick(now)
	# docs/01 §6.2 : le lien coupe au-dela du delai de grace fait perdre la
	# course. C'est le PC qui tranche, comme pour tout le reste.
	if _link_lost_since_ms >= 0 and now - _link_lost_since_ms > LINK_GRACE_MS:
		_link_lost_since_ms = -1
		engine.on_link_lost_beyond_grace()
	_watch_dropped_frames()


# --- Intentions de l'interface -----------------------------------------------

## Bascule simulateur / materiel — docs/05 lot 3, « en un clic ».
func apply_backend(use_simulator: bool) -> void:
	settings.use_simulator = use_simulator
	if use_simulator:
		_link.use_simulator()
	elif not _link.use_serial():
		# REPLI. Sortir ici est VOULU : `Link._swap` voit qu'un simulateur est
		# deja en place, garde celui qui tourne et jette le neuf. Poursuivre
		# jusqu'a `start()` relancerait un lien deja identifie, qui repasserait
		# par PORT_OPEN sous les yeux de l'operateur. Verifie en retirant la
		# bibliotheque native : le lien reste IDENTIFIED, START reste possible.
		settings.use_simulator = true
		_link.use_simulator()
		notice.emit(
			"Module natif absent : retour au simulateur. "
			+ "Compiler avec : cd addons/serial_link && scons target=template_debug"
		)
		return
	if not settings.preferred_port.is_empty():
		_link.set_preferred_port(settings.preferred_port)
	_link.start()
	notice.emit("lien : %s" % ("simulateur" if settings.use_simulator else "materiel"))


func set_preferred_port(port: String) -> void:
	settings.preferred_port = port
	_link.set_preferred_port(port)


func list_ports() -> Array:
	return _link.list_ports()


func link_state() -> int:
	return _link.get_link_state()


func firmware_version() -> String:
	return _link.get_firmware_version()


func link_stats() -> Dictionary:
	return _link.get_stats()


func is_simulated() -> bool:
	return _link.is_simulated()


func can_start_race() -> bool:
	# docs/01 §4 : IDENTIFIED est la SEULE condition d'autorisation du depart.
	return _link.can_start_race() and _engine_at_rest() and current_config().is_valid()


## Motif du refus, pour que le bouton grise puisse s'expliquer. Un bouton
## desactive sans raison visible est un appel au support en pleine soiree.
func start_blocked_reason() -> String:
	if not _link.can_start_race():
		return "lien %s — le boitier doit avoir repondu V: (docs/01 §4)" % (
			Protocol.state_name(_link.get_link_state())
		)
	if not _engine_at_rest():
		return "une course est deja en cours (%s)" % RaceEngine.state_label(engine.state())
	var problems := current_config().validate()
	if not problems.is_empty():
		return ", ".join(problems)
	return ""


## docs/02, FSM : FINISHED -> RESULTS -> NEW RACE -> IDLE. Une course terminee
## n'est pas « en cours » : le depart suivant est possible, et il n'a rien a
## interrompre.
## Une course est-elle en cours ? Armement et decompte compris : il y a alors
## quelque chose a arreter, et le boitier attend un `s`.
func race_in_progress() -> bool:
	return not _engine_at_rest()


func _engine_at_rest() -> bool:
	return engine.state() in [
		RaceEngine.State.IDLE, RaceEngine.State.FINISHED, RaceEngine.State.RESULTS
	]


func current_config() -> RaceConfig:
	return settings.to_race_config(roster.active_lanes())


func start_race() -> bool:
	var reason := start_blocked_reason()
	if not reason.is_empty():
		notice.emit("depart impossible : %s" % reason)
		return false
	# Un test capteurs en cours est une course a blanc cote boitier : la
	# terminer d'abord, sinon `g` tomberait sur un firmware deja parti.
	end_sensor_test()
	_silent_lanes_warned.clear()
	_dropped_warned = false
	# NEW RACE : la course precedente, terminee, est acquittee. Elle reste a
	# l'ecran public jusqu'au decompte suivant — c'est le HUD qui decide.
	acknowledge_results()
	var config := current_config()
	recorder.begin_race(config, roster.to_recorder_map())
	if not engine.arm(config, Time.get_ticks_msec()):
		notice.emit("armement refuse : %s" % engine.last_error())
		return false
	_link.set_race_active(true)
	return true


func stop_race() -> void:
	# Rien a interrompre apres une arrivee : STOP ou Relancer sur une course
	# terminee ecrivait RACE_ABORTED et affichait « COURSE INTERROMPUE » au
	# public — pour une course qui s'etait tres bien finie.
	if _engine_at_rest():
		return
	engine.abort("arret operateur")


## Relance : arrete puis rearme, en une seule intention.
func restart_race() -> bool:
	stop_race()
	return start_race()


func acknowledge_results() -> void:
	engine.show_results()
	engine.acknowledge_results()


## Test capteurs — docs/05 lot 3, docs/01 §5.7. Fait tourner chaque rouleau et
## verifie que les ticks arrivent sur la bonne piste. Sans lui, une inversion
## de cablage ne se decouvre qu'en pleine course.
##
## LE FIRMWARE NE LIT SES CAPTEURS QU'EN COURSE : au repos, un rouleau qui
## tourne ne produit rien. Le test est donc une course a blanc en mode temps —
## `x`, `t60`, `g`, la sequence sure de docs/01 §5.5 —, que le moteur n'arbitre
## pas : les CD: sont ignores (il est IDLE), les R: sont detournees vers
## `sensor_activity` avant lui, rien n'est journalise, et `s` y met fin.
func begin_sensor_test() -> void:
	if engine.state() != RaceEngine.State.IDLE and engine.state() != RaceEngine.State.RESULTS:
		notice.emit("test capteurs : impossible pendant une course")
		return
	_sensor_test_active = true
	for i: int in range(Protocol.MAX_RIDERS):
		_sensor_baseline[i] = 0
	for command: String in ["x", "t60", "g"]:
		if not _link.send_command(command):
			notice.emit("test capteurs : commande refusee par le lien : %s" % command)
			_sensor_test_active = false
			return
	notice.emit(
		"test capteurs : apres le decompte du boitier, tournez chaque rouleau,"
		+ " une piste a la fois"
	)


func end_sensor_test() -> void:
	if not _sensor_test_active:
		return
	_sensor_test_active = false
	_link.send_command("s")


func sensor_test_active() -> bool:
	return _sensor_test_active


func history() -> Array[RaceResult]:
	return _history


## Fermeture du logiciel. Une course en cours est ARRETEE proprement.
##
## Sans cela, `s` ne partait jamais : le firmware restait en course, ses LED
## allumees, et la sequence d'armement du lancement suivant tombait sur une
## course deja lancee (docs/01 §5.4). La trace de la course en cours etait
## perdue par la meme occasion, alors que tout autre abandon la conserve.
func shutdown() -> void:
	if not _engine_at_rest():
		engine.abort("fermeture du logiciel")
	save_preferences()


## Ecrit reglages et roster. Appele a chaque fin de course et a la fermeture
## — docs/02 §5 : un plantage en soiree ne doit rien perdre de ce qui a servi.
## Rend false et previent l'operateur si l'ecriture echoue.
func save_preferences() -> bool:
	if not preferences_enabled:
		return true
	var ok := settings.save(settings_path)
	if not ok:
		notice.emit("SAUVEGARDE DES REGLAGES : %s" % JsonStore.last_error)
	if not roster.save(roster_path):
		notice.emit("SAUVEGARDE DU ROSTER : %s" % JsonStore.last_error)
		ok = false
	return ok


## Accelere le temps du simulateur — demonstrations et tests.
func set_simulation_speed(scale: float) -> void:
	_link.set_simulation_speed(scale)


## Nombre de capteurs du boîtier SIMULÉ. Sans effet sur le matériel réel.
func set_simulator_riders(count: int) -> void:
	_link.set_simulator_riders(count)


## Profil du boîtier simulé — démonstrations et cas extrêmes.
func set_simulator_profile(name: String) -> bool:
	return _link.set_simulator_profile(name)


func simulator_profiles() -> Array:
	return _link.simulator_profiles()


## Câble arraché, puis rebranché — sur le boîtier SIMULÉ seulement.
func simulate_link_loss() -> void:
	_link.inject_link_loss()


func simulate_link_return() -> void:
	_link.inject_link_return()


## Un tick sans mouvement — rebond de contact — sur le boîtier SIMULÉ.
func simulate_phantom_tick(rider: int) -> void:
	_link.inject_phantom_tick(rider)


## Des trames perdues faute d'avoir suivi le flux — sur le boîtier SIMULÉ.
func simulate_dropped_frames(count: int) -> void:
	_link.inject_dropped_frames(count)


# --- Reactions au lien et au moteur ------------------------------------------

func _on_command_requested(command: String) -> void:
	if not _link.send_command(command):
		notice.emit("commande refusee par le lien : %s" % command)


func _on_link_state(state: int) -> void:
	_last_link_state = state
	link_state_changed.emit(state)
	if state == Protocol.State.LINK_LOST:
		_link_lost_since_ms = Time.get_ticks_msec()
		recorder.record_link_lost("lien perdu pendant la course")
		notice.emit("LIEN PERDU")
	else:
		_link_lost_since_ms = -1


func _on_frame(kind: int, payload: Dictionary) -> void:
	match kind:
		Protocol.Frame.PROGRESS:
			var ticks: Array = payload.get("ticks", [])
			var elapsed_ms := int(payload.get("elapsed_ms", 0))
			if _sensor_test_active:
				var raw := PackedInt32Array()
				raw.resize(Protocol.MAX_RIDERS)
				for i: int in range(Protocol.MAX_RIDERS):
					raw[i] = int(ticks[i]) if i < ticks.size() else 0
				sensor_activity.emit(raw)
				return
			engine.on_progress(ticks, elapsed_ms)
		Protocol.Frame.COUNTDOWN:
			engine.on_countdown(int(payload.get("value", 0)))
		Protocol.Frame.FALSE_START:
			engine.on_false_start(int(payload.get("rider", -1)))
		Protocol.Frame.RIDER_FINISH:
			# Observation bornee du boitier (docs/01 §5.6) : elle entre dans la
			# trace AVANT d'etre soumise au moteur, pour que le rejeu la revoie
			# au meme instant.
			var rider := int(payload.get("rider", -1))
			var elapsed_ms := int(payload.get("elapsed_ms", 0))
			recorder.record_hardware_finish(rider, elapsed_ms)
			engine.on_rider_finish(rider, elapsed_ms)
		Protocol.Frame.ERROR, Protocol.Frame.UNKNOWN:
			notice.emit("trame anormale : %s" % payload.get("text", ""))


func _on_progress_updated(state: RaceState) -> void:
	recorder.record_sample(state.ticks, state.elapsed_ms)
	_warn_silent_lanes(state)
	progress_updated.emit(state)


## Signale UNE FOIS par course chaque piste cochee restee muette.
func _warn_silent_lanes(state: RaceState) -> void:
	if state.elapsed_ms < SILENT_LANE_MS:
		return
	for rider: int in state.config.active_riders:
		if state.ticks[rider] > 0 or _silent_lanes_warned.has(rider):
			continue
		_silent_lanes_warned.append(rider)
		notice.emit(
			"PISTE %d : aucun tick depuis le depart — coureur absent"
			% (rider + 1)
			+ " ou capteur debranche ? La course attend cette piste."
		)


func _on_rider_finished(rider: int, elapsed_ms: int, rank: int) -> void:
	recorder.record_rider_finished(rider, elapsed_ms, rank)
	rider_finished.emit(rider, elapsed_ms, rank)


func _on_rider_eliminated(rider: int, rank: int, gap_m: float) -> void:
	recorder.record_rider_eliminated(rider, rank, gap_m)
	rider_eliminated.emit(rider, rank, gap_m)


func _on_false_start(rider: int, policy: RaceConfig.FalseStartPolicy) -> void:
	recorder.record_false_start(rider)
	false_start_detected.emit(rider, int(policy))


func _on_race_finished(result: RaceResult) -> void:
	_link.set_race_active(false)
	recorder.finish_race(result)
	_history.append(result)
	race_finished.emit(result)
	# Le classement est a l'ecran ; s'il n'est PAS sur disque, l'operateur
	# doit le savoir maintenant, pas en cherchant le CSV a la fin de la soiree.
	if not recorder.problems().is_empty():
		notice.emit("ENREGISTREMENT : %s" % recorder.problems()[recorder.problems().size() - 1])
	save_preferences()


func startup_problems() -> Array[String]:
	return _startup_problems


func _load_user_file(loader: Callable, label: String) -> void:
	loader.call()
	var error: String = JsonStore.last_error
	# Un fichier absent est le premier lancement, pas un probleme.
	if not error.is_empty() and not error.begins_with("fichier absent"):
		_startup_problems.append("%s : %s" % [label, error])


## docs/01 §6.3 : loggue au CSV, compte pour le panneau materiel, et dit a
## l'operateur. Le compte est celui de la SESSION : un capteur qui rebondit
## se voit d'une course a l'autre.
func _on_tick_rejected(rider: int, description: String) -> void:
	_rejected_ticks += 1
	_last_rejection = description
	recorder.record_tick_rejected(rider, description)
	notice.emit("tick rejete : %s" % description)


## `DEPANNAGE` : des trames perdues sont LE SEUL CAS qui fausse reellement une
## mesure — la machine ne suit plus le flux et des ticks manquent pour de bon.
## Le compteur vivait dans une ligne de statistiques que personne ne lit
## pendant une soiree : le defaut le plus grave etait le plus discret.
##
## Signale UNE FOIS par course : le compteur ne redescend jamais, repeter a
## chaque image noierait le reste.
func _watch_dropped_frames() -> void:
	if _dropped_warned or not race_in_progress():
		return
	if int(_link.get_stats().get("frames_dropped", 0)) <= 0:
		return
	_dropped_warned = true
	notice.emit(
		"TRAMES PERDUES : la machine ne suit plus le flux du boitier."
		+ " Fermer les autres applications — c'est le seul cas qui fausse une mesure."
	)


## La pointe est RETENUE — elle est peut-etre vraie —, seulement signalee.
## `DEPANNAGE` : au-dela, c'est un capteur qui rebondit ou un aimant qui passe
## deux fois par tour.
func _on_speed_implausible(rider: int, kph: float) -> void:
	notice.emit(
		"PISTE %d : pointe a %.0f km/h — capteur qui rebondit"
		% [rider + 1, kph]
		+ " ou aimant qui passe deux fois par tour ? La mesure est conservee."
	)


func rejected_ticks() -> int:
	return _rejected_ticks


func last_rejection() -> String:
	return _last_rejection


func _on_race_aborted(note: String) -> void:
	_link.set_race_active(false)
	# La trace AVANT le marqueur d'abandon : le CSV se lit alors « voila ou en
	# etait chacun », puis « et voila pourquoi ca s'est arrete ».
	var partial := engine.result()
	if partial != null:
		recorder.finish_race(partial)
		_history.append(partial)
	recorder.record_abort(note)
	race_aborted.emit(note)
	save_preferences()
