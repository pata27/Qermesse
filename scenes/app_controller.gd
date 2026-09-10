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
## Le roster a change autrement que par une course — une couleur choisie pour
## coller au velo pose sur les rouleaux. L'ecran public s'y aligne aussitot.
signal roster_changed()
## Ticks bruts par piste, pour le test capteurs du panneau materiel.
signal sensor_activity(ticks: PackedInt32Array)
## Le test capteurs commence ou finit — par le bouton, par un START qui y met
## fin, ou par un lien qui tombe. Le bouton a bascule du panneau materiel se
## resynchronise dessus : il restait enfonce apres un START et disait un test
## en cours quand il n'y en avait plus.
signal sensor_test_changed(active: bool)
## Le mode demo commence ou finit. START, Relancer et Test capteurs s'y
## regrisent : une vraie course lancee entre deux manches de vitrine partait
## enregistreur MUET — perdue —, et la vitrine reprenait par-dessus son podium.
signal demo_mode_changed(active: bool)

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
## Fraction de l'epreuve au-dela de laquelle une piste muette se signale, meme
## si les dix secondes ne sont pas ecoulees.
##
## LE SEUIL ABSOLU ARRIVE TROP TARD, et c'est le meme piege que la cloche de
## fin. La distance MINIMALE que la configuration accepte est de 50 m : quatre
## secondes a 45 km/h. Sur 100 m, huit secondes. L'alerte des dix secondes
## tombait donc APRES l'instant ou la course aurait du se terminer.
##
## Elle finissait par venir — le chrono continue de courir, puisque le PC attend
## justement la piste manquante — mais huit secondes trop tard, pendant
## lesquelles le public regarde une course qui visiblement aurait du finir.
## Mesure sur 100 m avec une piste vide : 10,0 s avant, 2,1 s apres. Un repere
## absolu se plafonne a une fraction de l'epreuve.
const SILENT_LANE_SHARE := 0.25

## Silence tolere APRES des ticks : au-dela, la piste s'est eteinte en route.
##
## L'autre garde ne voit que les pistes muettes DEPUIS LE DEPART. Or un capteur
## lache bien plus volontiers pendant l'effort qu'avant : cable arrache par la
## secousse, aimant qui part, coureur qui s'arrete. Cette piste-la produisait
## des ticks, donc rien ne la signalait — et en distance la course l'attend
## jusqu'au plafond de dix minutes, devant le public, sans un mot.
##
## Un tick vaut un tour de rouleau, 36 cm au rouleau standard : cinq secondes
## sans un seul tick, c'est un arret ou un capteur mort, jamais une allure
## lente — il faudrait rouler sous 0,3 km/h.
const STALLED_LANE_MS := 5000

## Coutures de test, a fixer AVANT l'entree dans l'arbre. En production elles
## gardent leurs valeurs par defaut ; en test elles evitent d'ecrire dans les
## donnees de l'utilisateur et de dependre de ses reglages.
## VITRINE : des coureurs synthétiques occupent l'écran, personne ne pédale.
##
## Rien de ce qui s'y passe n'a eu lieu. Le `Recorder` est rendu muet, la course
## n'entre pas dans « Courses du jour », et les réglages ne sont pas sauvés —
## sans quoi la vitrine écraserait la configuration que l'opérateur avait posée
## pour sa vraie course suivante.
var demo_mode := false:
	set(value):
		var changed := demo_mode != value
		demo_mode = value
		if recorder != null:
			recorder.muted = value
		if changed:
			demo_mode_changed.emit(value)

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
## Derniere longueur demandee au boitier, en ticks — pour la confronter a son
## accuse `L:`. Negative tant qu'aucune course en distance n'a ete armee.
var _requested_length_ticks := -1
## Pistes deja signalees comme muettes, pour ne le dire qu'une fois par course.
var _silent_lanes_warned: Array[int] = []
var _stalled_lanes_warned: Array[int] = []
## Dernier compteur vu par piste, et l'instant FIRMWARE ou il a bouge.
var _last_tick_count := PackedInt32Array()
var _last_tick_ms := PackedInt32Array()
var _dropped_warned := false
var _link: Link = null
var _link_lost_since_ms: int = -1
var _rejected_ticks: int = 0
## Trames `G`/`S` d'un shield kiosque, comptees pour la session — docs/06 §4.
var _kiosk_frames: int = 0
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
		# UN FICHIER LISIBLE MAIS FAUX EST DIT AUSSI. Chaque valeur ramenee dans
		# ses bornes ou remplacee par defaut est nommee, avec ce qui a ete lu et
		# ce qui est garde : l'operateur qui a edite le fichier a la main sait
		# quoi verifier avant la premiere course.
		var corrected := settings.corrections()
		if not corrected.is_empty():
			_startup_problems.append(
				"REGLAGES : %d valeur(s) corrigée(s) dans settings.json — %s"
				% [corrected.size(), " ; ".join(corrected)]
			)
		_load_user_file(roster.load_from.bind(roster_path), "ROSTER")
		var roster_fixed := roster.corrections()
		if not roster_fixed.is_empty():
			_startup_problems.append(
				"ROSTER : %d valeur(s) corrigée(s) dans roster.json — %s"
				% [roster_fixed.size(), " ; ".join(roster_fixed)]
			)

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
	# LE DISQUE SE VERIFIE LA VEILLE. Un dossier de resultats non inscriptible
	# n'etait decouvert qu'au premier « ENREGISTREMENT : … », a la fin de la
	# premiere course, devant le public. La ligne orange le dit au lancement.
	var unwritable := recorder.check_writable()
	if not unwritable.is_empty():
		_startup_problems.append(
			"RÉSULTATS : rien ne pourra être enregistré — %s" % " ; ".join(unwritable)
		)
	# Un redemarrage en pleine soiree ne vide pas « Courses du jour ».
	_history = recorder.load_day()
	# ET IL DIT CE QU'IL N'A PAS SU RELIRE. Une course ecartee disparaissait de
	# la liste sans un mot : l'operateur se retrouvait avec onze lignes pour
	# douze manches, sans savoir laquelle manquait. Le CSV du jour, lui, garde
	# ses lignes — c'est la premiere chose a dire a quelqu'un qui cherche une
	# course absente.
	var unreadable := recorder.last_scan_unreadable()
	if not unreadable.is_empty():
		_startup_problems.append(
			"COURSES DU JOUR : %d fichier(s) de course illisible(s), la liste est incomplète"
			% unreadable.size()
			+ " — le journal CSV du jour, lui, garde ses lignes. Fichiers : %s"
			% ", ".join(unreadable)
		)

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
## ON NE CHANGE PAS DE BOITIER EN PLEINE COURSE. Basculer materiel/simulateur
## remplace le lien : le moteur restait « course en cours » sur un lien
## DISCONNECTED — ni LIEN PERDU, ni abandon a trois secondes, une course figee
## sans autre issue que STOP, et un boitier reel toujours en course. Mesure.
## STOP d'abord, puis la bascule : c'est aussi l'ordre de la fiche « Rien ne
## fonctionne et le public attend ».
func apply_backend(use_simulator: bool) -> void:
	if race_in_progress():
		notice.emit("lien : pas de changement de boîtier pendant une course — STOP d'abord")
		return
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


## DEDUIT DU MOTIF, pas recopie. Les deux fonctions listaient chacune leurs
## conditions ; le mode demo ajoute au motif ne grisait pas le bouton, qui
## disait « Lancer la course » sur un depart que `start_race` refusait.
func can_start_race() -> bool:
	return start_blocked_reason().is_empty()


## Motif du refus, pour que le bouton grise puisse s'expliquer. Un bouton
## desactive sans raison visible est un appel au support en pleine soiree.
## `from_demo` : la vitrine lance ses propres manches pendant le mode demo ;
## l'operateur, lui, en est empeche tant qu'elle tourne. Une vraie course
## partie entre deux manches — le moteur y est au repos, START etait
## disponible — courait enregistreur muet et n'entrait pas dans Courses du
## jour : mesure, historique a zero apres l'arrivee. Et la vitrine reprenait
## par-dessus son podium a la respiration suivante.
func start_blocked_reason(from_demo: bool = false) -> String:
	if demo_mode and not from_demo:
		return "mode démo en cours — l'arrêter d'abord (panneau Fenêtre spectacle)"
	if not _link.can_start_race():
		return "lien %s — le boîtier doit avoir répondu V: (docs/01 §4)" % (
			Protocol.state_name(_link.get_link_state())
		)
	if not _engine_at_rest():
		return "une course est déjà en cours (%s)" % RaceEngine.state_label(engine.state())
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


func start_race(from_demo: bool = false) -> bool:
	var reason := start_blocked_reason(from_demo)
	if not reason.is_empty():
		notice.emit("départ impossible : %s" % reason)
		return false
	# Un test capteurs en cours est une course a blanc cote boitier : la
	# terminer d'abord, sinon `g` tomberait sur un firmware deja parti.
	end_sensor_test()
	_silent_lanes_warned.clear()
	_stalled_lanes_warned.clear()
	_last_tick_count = PackedInt32Array()
	_last_tick_count.resize(Protocol.MAX_RIDERS)
	_last_tick_ms = PackedInt32Array()
	_last_tick_ms.resize(Protocol.MAX_RIDERS)
	_dropped_warned = false
	# NEW RACE : la course precedente, terminee, est acquittee. Elle reste a
	# l'ecran public jusqu'au decompte suivant — c'est le HUD qui decide.
	acknowledge_results()

	var config := current_config()
	recorder.begin_race(config, roster.to_recorder_map())
	if not engine.arm(config, Time.get_ticks_msec()):
		notice.emit("armement refusé : %s" % engine.last_error())
		return false
	_link.set_race_active(true)
	return true


func stop_race() -> void:
	# Rien a interrompre apres une arrivee : STOP ou Relancer sur une course
	# terminee ecrivait RACE_ABORTED et affichait « COURSE INTERROMPUE » au
	# public — pour une course qui s'etait tres bien finie.
	if _engine_at_rest():
		return
	engine.abort("arrêt opérateur")


## Relance : arrete puis rearme, en une seule intention.
func restart_race() -> bool:
	stop_race()
	return start_race()


## Referme l'ecran de resultats. `show_results()` reste appele en premier : le
## moteur y est deja passe a la fin de la course, mais si un chemin l'avait
## laisse a FINISHED, l'armement suivant serait refuse — et un depart bloque
## en pleine soiree coute plus cher qu'un appel sans effet.
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
	if demo_mode:
		# Entre deux manches le moteur est au repos, mais le boitier simule
		# appartient a la vitrine : une course a blanc tomberait sur sa manche.
		notice.emit("test capteurs : impossible pendant le mode démo")
		return
	_sensor_test_active = true
	for i: int in range(Protocol.MAX_RIDERS):
		_sensor_baseline[i] = 0
	for command: String in ["x", "t60", "g"]:
		if not _link.send_command(command):
			notice.emit("test capteurs : commande refusée par le lien : %s" % command)
			_sensor_test_active = false
			return
	notice.emit(
		"test capteurs : après le décompte du boîtier, tournez chaque rouleau,"
		+ " une piste à la fois"
	)
	sensor_test_changed.emit(true)


func end_sensor_test() -> void:
	if not _sensor_test_active:
		return
	_sensor_test_active = false
	_link.send_command("s")
	sensor_test_changed.emit(false)


func sensor_test_active() -> bool:
	return _sensor_test_active


## La scene s'est allegee d'elle-meme sous les 60 fps (docs/04 §4). Une
## decision prise sans l'operateur lui est dite : sans ce message, l'image
## changeait et personne n'expliquait pourquoi.
func report_quality_degraded(level_name: String) -> void:
	notice.emit(
		"QUALITÉ : la scène s'est allégée à %s — la machine ne tenait pas 60 fps" % level_name
	)


func history() -> Array[RaceResult]:
	return _history


## Fermeture du logiciel. Une course en cours est ARRETEE proprement.
##
## Sans cela, `s` ne partait jamais : le firmware restait en course, ses LED
## allumees, et la sequence d'armement du lancement suivant tombait sur une
## course deja lancee (docs/01 §5.4). La trace de la course en cours etait
## perdue par la meme occasion, alors que tout autre abandon la conserve.
func shutdown() -> void:
	# UN TEST CAPTEURS EST UNE COURSE A BLANC COTE BOITIER. Le moteur, lui, est
	# au repos : sans ce `s`, fermer le logiciel pendant le test laissait le
	# boitier en course, LED allumees, et il refusait de repartir droit au
	# lancement suivant — precisement ce que le manuel §6 promet d'eviter.
	end_sensor_test()
	if not _engine_at_rest():
		engine.abort("fermeture du logiciel")
	save_preferences()


## Ecrit reglages et roster. Appele a chaque fin de course et a la fermeture
## — docs/02 §5 : un plantage en soiree ne doit rien perdre de ce qui a servi.
## Rend false et previent l'operateur si l'ecriture echoue.
func save_preferences() -> bool:
	if not preferences_enabled:
		return true
	# LA VITRINE N'ECRIT RIEN, et la garde est posee ICI plutot que chez les
	# appelants. Elle ecrase mode, distance, pistes actives et jusqu'au choix
	# du backend le temps de sa demonstration, et les rend a l'arret ; toute
	# sauvegarde entre les deux graverait ses valeurs a la place de celles de
	# l'operateur.
	#
	# Trois appelants, et c'est le troisieme qui l'a montre : la fermeture du
	# logiciel sauve sans condition. Fermer pendant la vitrine remplacait donc
	# silencieusement la configuration de la soiree par le dernier scenario de
	# demonstration — simulateur force compris, si bien qu'au lancement suivant
	# le vrai boitier n'etait plus utilise. Une garde par appelant, c'est une
	# garde a oublier ; une seule sur la porte de sortie ne s'oublie pas.
	if demo_mode:
		return true
	var ok := settings.save(settings_path)
	if not ok:
		notice.emit("SAUVEGARDE DES REGLAGES : %s" % JsonStore.last_error)
	if not roster.save(roster_path):
		notice.emit("SAUVEGARDE DU ROSTER : %s" % JsonStore.last_error)
		ok = false
	return ok


## Accelere le temps du simulateur — demonstrations et tests.
## Couleur d'une piste — docs/04 §2. Passe par le controleur et non par le
## roster directement : c'est lui qui previent l'ecran public, qui n'a aucun
## lien avec le panneau operateur.
func set_rider_color(lane: int, color: String) -> bool:
	if not roster.set_color(lane, color):
		return false
	roster_changed.emit()
	return true


## Rend une piste a sa couleur de charte.
func reset_rider_color(lane: int) -> void:
	roster.reset_color(lane)
	roster_changed.emit()


func set_simulation_speed(scale: float) -> void:
	_link.set_simulation_speed(scale)


## Nombre de capteurs du boîtier SIMULÉ. Sans effet sur le matériel réel.
func set_simulator_riders(count: int) -> void:
	_link.set_simulator_riders(count)


## Profil du boîtier simulé — démonstrations et cas extrêmes.
func set_simulator_profile(name: String) -> bool:
	return _link.set_simulator_profile(name)


func simulation_speed() -> float:
	return _link.simulation_speed()


## Ce que le simulateur porte en ce moment — la vitrine l'emprunte et le rend.
func simulator_profile() -> String:
	return _link.simulator_profile()


func simulator_riders() -> int:
	return _link.simulator_riders()


func simulator_profiles() -> Array:
	return _link.simulator_profiles()


## Câble arraché, puis rebranché — sur le boîtier SIMULÉ seulement.
func simulate_link_loss() -> void:
	_link.inject_link_loss()


func simulate_link_return() -> void:
	_link.inject_link_return()


## Un rider qui pédale pendant le décompte — sur le boîtier SIMULÉ.
##
## Cette couture manquait, seule des cinq injections du simulateur. Résultat :
## `FALSE_START` était le seul événement du CSV qu'aucun test n'atteignait, et
## `docs/RECETTE.md` §7 le faisait cocher à la main, boîtier branché.
func simulate_false_start(rider: int) -> void:
	_link.inject_false_start(rider)


## Un tick sans mouvement — rebond de contact — sur le boîtier SIMULÉ.
func simulate_phantom_tick(rider: int) -> void:
	_link.inject_phantom_tick(rider)


## Un accusé de longueur différent de celui demandé — sur le boîtier SIMULÉ.
func simulate_length_ack(ticks: int) -> void:
	_link.inject_length_ack(ticks)


## Une trame illisible sur la ligne — sur le boîtier SIMULÉ.
func simulate_corrupt_frame() -> void:
	_link.inject_corrupt_frame()


## Des trames perdues faute d'avoir suivi le flux — sur le boîtier SIMULÉ.
func simulate_dropped_frames(count: int) -> void:
	_link.inject_dropped_frames(count)


# --- Reactions au lien et au moteur ------------------------------------------

func _on_command_requested(command: String) -> void:
	# LA LONGUEUR DEMANDEE EST RETENUE, pour être confrontée à l'accusé `L:`.
	# C'est la seule chose que le boîtier nous dise de ce qu'il a compris.
	if command.begins_with("l"):
		_requested_length_ticks = int(command.substr(1))
	if not _link.send_command(command):
		notice.emit("commande refusée par le lien : %s" % command)


func _on_link_state(state: int) -> void:
	_last_link_state = state
	link_state_changed.emit(state)
	# UN TEST CAPTEURS NE SURVIT PAS AU LIEN. La course a blanc vivait dans le
	# boitier ; debranche, il l'oublie, et au rebranchement il repart au repos.
	# Garder le test « actif » ici, c'est un bouton enfonce qui ment, et des
	# trames R: detournees vers un affichage que personne ne regarde plus.
	if (
		_sensor_test_active
		and state in [Protocol.State.LINK_LOST, Protocol.State.DISCONNECTED]
	):
		_sensor_test_active = false
		notice.emit("test capteurs : interrompu, lien perdu")
		sensor_test_changed.emit(false)
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
			# LA TRACE PORTE LA TRAME BRUTE, avant filtrage et avant le gel
			# d'un rider arrive. `docs/02` §5 promet « la trace complète des
			# trames R: » ; elle portait les valeurs RETENUES par le filtre, si
			# bien qu'un tick rejeté — ce que `DEPANNAGE` fait précisément
			# diagnostiquer en envoyant ce fichier — disparaissait du fichier
			# envoyé. Le symptôme était au CSV, la preuve nulle part.
			#
			# Enregistrée APRÈS l'appel : c'est cette trame-là qui fait passer
			# le moteur de COUNTDOWN à RUNNING, et la sauter perdrait la
			# première ligne de la course.
			var live := (
				engine.state() == RaceEngine.State.COUNTDOWN
				or engine.state() == RaceEngine.State.RUNNING
			)
			engine.on_progress(ticks, elapsed_ms)
			if live:
				var raw_ticks := PackedInt32Array()
				raw_ticks.resize(Protocol.MAX_RIDERS)
				for i: int in range(Protocol.MAX_RIDERS):
					raw_ticks[i] = int(ticks[i]) if i < ticks.size() else 0
				recorder.record_sample(raw_ticks, elapsed_ms)
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
		Protocol.Frame.LENGTH_ACK:
			_check_length_ack(int(payload.get("ticks", -1)))
		Protocol.Frame.ERROR, Protocol.Frame.UNKNOWN:
			notice.emit("trame anormale : %s" % payload.get("text", ""))
		Protocol.Frame.KIOSK_START, Protocol.Frame.KIOSK_STOP:
			# `docs/06` §4 : « trames G/S reellement emises par un shield kiosque
			# — parsees et loggees, comportement active seulement si observe ».
			# `ss_monitor` les journalise deja ; l'application, elle, les jetait.
			# Or c'est en soiree qu'un tel boitier se revelerait, et le monitor
			# ne tourne pas ce soir-la. Comptees, pas commentees : une notice par
			# trame noierait le journal si le shield en emet en continu.
			_kiosk_frames += 1
		Protocol.Frame.VERSION, Protocol.Frame.MOCK_ACK:
			# IGNOREES, ET C'EST DELIBERE. `V:` est consommee par la couche lien,
			# qui en fait l'etat IDENTIFIED (docs/01 §4) ; `M:` accuse la commande
			# `m`, que la v3 n'emet jamais (docs/01 §2). Les nommer ici plutot que
			# de les laisser tomber dans le silence du `match` : le test
			# `test_aucune_trame_ne_tombe_dans_le_silence` l'exige.
			pass


## Confronte l'accusé `L:` du boîtier à la longueur qu'on lui a demandée.
##
## `docs/01` §2 : `l<ticks>` est la SEULE commande dont le firmware accuse
## réception. Cet accusé était reçu, parsé, et jeté. Or `docs/06` §4 liste « le
## firmware réel diverge de `ss_basic.ino` » parmi les risques forts : un
## boîtier reflashé qui borne ou tronque la longueur allumerait ses LED
## d'arrivée au mauvais endroit, devant le public, sans que rien ne l'annonce.
##
## Le classement, lui, ne bouge pas : c'est le PC qui arbitre (docs/01 §5.4).
## C'est bien pour cela qu'il faut le DIRE — sinon l'écart entre les LED du
## boîtier et l'écran passerait pour un bug du logiciel.
func _check_length_ack(ticks: int) -> void:
	if ticks < 0 or _requested_length_ticks < 0 or ticks == _requested_length_ticks:
		return
	notice.emit(
		"LONGUEUR : le boîtier a compris %d ticks, %d demandés — ses LED d'arrivée"
		% [ticks, _requested_length_ticks]
		+ " seront à la mauvaise distance. Le classement, lui, reste arbitré par le PC."
	)


func _on_progress_updated(state: RaceState) -> void:
	_warn_silent_lanes(state)
	_warn_stalled_lanes(state)
	progress_updated.emit(state)


## Signale UNE FOIS par course chaque piste cochee restee muette.
func _warn_silent_lanes(state: RaceState) -> void:
	if not _silent_lanes_due(state):
		return
	for rider: int in state.config.active_riders:
		if state.ticks[rider] > 0 or _silent_lanes_warned.has(rider):
			continue
		_silent_lanes_warned.append(rider)
		notice.emit(
			"PISTE %d : aucun tick depuis le départ — coureur absent"
			% (rider + 1)
			+ " ou capteur débranché ? "
			+ _lane_consequence(state)
		)


## CE QUE LA COURSE FERA D'UNE PISTE MUETTE, selon le mode. « La course attend
## cette piste » n'etait vrai qu'en distance, ou tout le monde va au bout. En
## temps le gong tombe quand meme, et un operateur qui lisait « attend »
## pouvait arreter une course qui allait finir seule ; en poursuite le muet est
## elimine des que l'ecart est atteint. La phrase dit quoi faire — elle doit
## donc etre vraie dans le mode joue.
static func _lane_consequence(state: RaceState) -> String:
	match state.config.mode:
		RaceConfig.Mode.TIME:
			return "La course finira au gong quand même ; cette piste marquera zéro."
		RaceConfig.Mode.PURSUIT:
			return "Elle sera éliminée dès que l'écart décisif sera atteint."
	return "La course attend cette piste."


## Est-on assez avance dans l'epreuve pour qu'une piste muette soit anormale ?
##
## Dix secondes, OU le quart de l'epreuve — le premier des deux. La fraction se
## mesure sur ce qui DEFINIT le mode : la distance parcourue par le premier en
## mode distance, le temps ecoule en mode temps. La poursuite s'en tient aux dix
## secondes : sa fin depend d'un ecart qui se referme, et rien n'y permet de
## dire ou l'on en est.
static func _silent_lanes_due(state: RaceState) -> bool:
	if state.elapsed_ms >= SILENT_LANE_MS:
		return true
	match state.config.mode:
		RaceConfig.Mode.DISTANCE:
			var leader := 0.0
			for rider: int in state.config.active_riders:
				leader = maxf(leader, state.distance_m[rider])
			return leader >= state.config.distance_m * SILENT_LANE_SHARE
		RaceConfig.Mode.TIME:
			var share := state.config.duration_s * 1000.0 * SILENT_LANE_SHARE
			return float(state.elapsed_ms) >= share
	return false


## Signale UNE FOIS par course chaque piste qui s'est TUE EN ROUTE.
##
## Distincte de la piste muette depuis le depart, et volontairement : le motif
## n'est pas le meme, et le message non plus. Ici la piste a bel et bien
## fonctionne, donc ni le cablage ni la case cochee ne sont en cause — c'est
## arrive pendant la course.
##
## Rien n'est signale pour une piste qui a fini de courir : arrivee ou
## eliminee, son silence est normal, et l'accuser serait crier au loup a chaque
## fin de course.
func _warn_stalled_lanes(state: RaceState) -> void:
	if _last_tick_ms.size() < Protocol.MAX_RIDERS:
		return
	for rider: int in state.config.active_riders:
		var ticks := state.ticks[rider]
		if ticks != _last_tick_count[rider]:
			_last_tick_count[rider] = ticks
			_last_tick_ms[rider] = state.elapsed_ms
			continue
		# Muette depuis le depart : l'autre garde s'en charge, avec ses mots.
		if ticks == 0 or _stalled_lanes_warned.has(rider):
			continue
		if state.finished_ms[rider] > 0 or state.eliminated[rider]:
			continue
		var silence_ms := state.elapsed_ms - _last_tick_ms[rider]
		if silence_ms < STALLED_LANE_MS:
			continue
		_stalled_lanes_warned.append(rider)
		notice.emit(
			"PISTE %d : plus un seul tick depuis %.0f s alors qu'elle roulait"
			% [rider + 1, silence_ms / 1000.0]
			+ " — coureur arrêté ou capteur perdu en route ? "
			+ _lane_consequence(state)
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
	# UNE COURSE DE DEMONSTRATION N'A PAS EU LIEU. Le `Recorder` est muet, mais
	# « Courses du jour » se remplit depuis CETTE liste, et les reglages se
	# sauvent ici : sans ces deux gardes, la vitrine repeuplerait l'historique
	# de la soiree avec des coureurs qui n'existent pas.
	if not demo_mode:
		_history.append(result)
	race_finished.emit(result)
	_report_recording_problems()
	save_preferences()
	# LE RESULTAT EST A L'ECRAN : la FSM le dit. `docs/02` §1 fait suivre
	# FINISHED de RESULTS, « resultat consultable, en attente d'acquittement » ;
	# c'est un etat ou l'on sejourne, le temps que l'operateur regarde le
	# classement. Il etait traverse en une microseconde au depart de la course
	# SUIVANTE, si bien que le moteur restait a FINISHED tout le temps ou le
	# podium etait affiche, et que l'etape decrite par le diagramme n'existait
	# nulle part. On y entre ici, apres avoir prevenu tout le monde.
	engine.show_results()


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
	notice.emit("tick rejeté : %s" % description)


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
		"TRAMES PERDUES : la machine ne suit plus le flux du boîtier."
		+ " Fermer les autres applications — c'est le seul cas qui fausse une mesure."
	)


## La pointe est RETENUE — elle est peut-etre vraie —, seulement signalee.
## `DEPANNAGE` : au-dela, c'est un capteur qui rebondit ou un aimant qui passe
## deux fois par tour.
func _on_speed_implausible(rider: int, kph: float) -> void:
	notice.emit(
		"PISTE %d : pointe à %.0f km/h — capteur qui rebondit"
		% [rider + 1, kph]
		+ " ou aimant qui passe deux fois par tour ? La mesure est conservée."
	)


func rejected_ticks() -> int:
	return _rejected_ticks


## Trames kiosque vues depuis le lancement. Zero sur un boitier ordinaire ; tout
## autre chiffre est une information qu'on veut avoir, et qu'on n'avait pas.
func kiosk_frames() -> int:
	return _kiosk_frames


func last_rejection() -> String:
	return _last_rejection


func _on_race_aborted(note: String) -> void:
	_link.set_race_active(false)
	# La trace AVANT le marqueur d'abandon : le CSV se lit alors « voila ou en
	# etait chacun », puis « et voila pourquoi ca s'est arrete ».
	var partial := engine.result()
	if partial != null:
		recorder.finish_race(partial)
		# MEME GARDE QU'A L'ARRIVEE. Arreter la vitrine abandonne la manche en
		# cours, et ce chemin-ci ecrivait le resultat partiel dans « Courses du
		# jour » : eteindre la demonstration ajoutait une course INTERROMPUE que
		# personne n'avait courue, juste avant la vraie soiree.
		if not demo_mode:
			_history.append(partial)
	recorder.record_abort(note)
	# MEME ALERTE QU'A L'ARRIVEE : une course interrompue dont la trace ne
	# s'ecrit pas se taisait, alors que c'est precisement celle que DEPANNAGE
	# fait envoyer au developpeur.
	_report_recording_problems()
	race_aborted.emit(note)


## Le classement est a l'ecran ; s'il n'est PAS sur disque, l'operateur doit le
## savoir maintenant, pas en cherchant le CSV a la fin de la soiree.
func _report_recording_problems() -> void:
	if recorder.problems().is_empty():
		return
	notice.emit("ENREGISTREMENT : %s" % recorder.problems()[recorder.problems().size() - 1])
	save_preferences()
