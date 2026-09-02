## ss_monitor — outil console de validation du lien serie.
##
## C'est l'outil du jalon J1 : il passe par le GDExtension, donc par le code
## reellement embarque dans le logiciel. Contrairement a `tools/ss_probe.py`,
## qui est un temoin independant, celui-ci prouve la chaine de production.
##
##   godot --headless --script tools/ss_monitor.gd -- [--port <chemin>] [--duree <s>]
##                                                    [--sim] [--distance <m>]
##
## Affiche en direct : etat du lien, version firmware, ticks et distance des
## quatre pistes, trames anormales, statistiques.
extends SceneTree

const REFRESH_S := 0.1

var _link: Node = null
var _port := ""
var _duration := 0.0
var _use_sim := false
var _distance_m := 0.0
var _elapsed := 0.0
var _ticks := [0, 0, 0, 0]
var _elapsed_ms := 0
var _events: Array[String] = []
var _armed := false
var _roller_mm := Protocol.DEFAULT_ROLLER_MM


func _initialize() -> void:
	_parse_args()

	if _use_sim:
		_link = (load("res://hardware/link_sim.gd") as GDScript).new()
		root.add_child(_link)
		print("mode            : SIMULATEUR (aucun materiel requis)")
	elif not ClassDB.class_exists("SerialLink"):
		printerr("Le module natif SerialLink n'est pas compile.")
		printerr("  cd addons/serial_link && scons target=template_debug")
		quit(2)
		return
	else:
		_link = ClassDB.instantiate("SerialLink")
		root.add_child(_link)
		print("mode            : MATERIEL (via GDExtension)")
		_print_ports()

	_link.frame_received.connect(_on_frame)
	_link.state_changed.connect(_on_state)

	if not _port.is_empty():
		_link.set_preferred_port(_port)
		print("port force      : %s" % _port)
	if _use_sim:
		_link.start()
	else:
		_link.start_autoconnect()
	print("")


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--port":
				i += 1
				_port = args[i] if i < args.size() else ""
			"--duree":
				i += 1
				_duration = float(args[i]) if i < args.size() else 0.0
			"--distance":
				i += 1
				_distance_m = float(args[i]) if i < args.size() else 0.0
			"--rouleau-mm":
				i += 1
				_roller_mm = float(args[i]) if i < args.size() else _roller_mm
			"--sim":
				_use_sim = true
			_:
				printerr("option inconnue : %s" % args[i])
		i += 1


## Liste TOUS les ports, pas seulement les candidats.
##
## `docs/RECETTE.md` §1 demande de verifier deux choses le jour du boitier :
## que sa ligne apparait marquee CANDIDAT, et que les autres sont marques
## `ignore` — donc qu'aucun ne sera ouvert au hasard, la faute de la v1. Seuls
## les candidats etaient imprimes : la seconde verification etait impossible
## avec l'outil que la recette nomme.
func _print_ports() -> void:
	var ports: Array = _link.list_ports()
	var candidates: Array = ports.filter(func(p: Dictionary) -> bool:
		return bool(p.get("candidate", false)))
	print("ports detectes  : %d, dont %d candidat(s)" % [ports.size(), candidates.size()])
	# Les candidats d'abord : c'est la ligne qu'on cherche des yeux.
	var ordered: Array = candidates.duplicate()
	for p: Dictionary in ports:
		if not bool(p.get("candidate", false)):
			ordered.append(p)
	for p: Dictionary in ordered:
		var ids := "sans VID/PID"
		if int(p.get("vid", -1)) >= 0:
			ids = "%04x:%04x" % [int(p["vid"]), int(p["pid"])]
		print(
			"  %-8s %-24s %-13s %s"
			% [
				"CANDIDAT" if bool(p.get("candidate", false)) else "ignore",
				p.get("port", "?"),
				ids,
				p.get("reason", ""),
			]
		)
	if candidates.is_empty():
		# C'est le comportement voulu, pas une panne : la v1 aurait ouvert le
		# dernier port de la liste, c'est-a-dire n'importe quoi.
		print("  aucun port ne coche de critere — aucun ne sera ouvert au hasard")
		print("  (un pseudo-terminal n'apparait pas ici : utiliser --port)")


func _on_state(state: int) -> void:
	_note("lien -> %s" % Protocol.state_name(state))
	if state == Protocol.State.IDENTIFIED and not _armed:
		_armed = true
		_note("firmware %s sur %s" % [_link.get_firmware_version(), _link.get_current_port()
			if _link.has_method("get_current_port") else "?"])
		if _distance_m > 0.0:
			_arm_race()


func _arm_race() -> void:
	var ticks := Protocol.ticks_for_metres(_distance_m, _roller_mm)
	if not Protocol.is_valid_firmware_argument(ticks):
		_note("distance hors bornes firmware : %d ticks" % ticks)
		return
	# docs/01 §2 : d ou x, puis l ou t, puis g — dans cet ordre, sans rien
	# intercaler entre la commande et son terminateur.
	_link.send_command("d")
	_link.send_command("l%d" % ticks)
	_link.send_command("g")
	_link.set_race_active(true)
	_note("course armee : %.0f m = %d ticks" % [_distance_m, ticks])


func _on_frame(kind: int, payload: Dictionary) -> void:
	match kind:
		Protocol.Frame.PROGRESS:
			_ticks = payload.get("ticks", _ticks)
			_elapsed_ms = int(payload.get("elapsed_ms", 0))
		Protocol.Frame.COUNTDOWN:
			_note("decompte %d" % int(payload.get("value", -1)))
		Protocol.Frame.RIDER_FINISH:
			_note(
				"ARRIVEE piste %d a %d ms"
				% [int(payload.get("rider", -1)), int(payload.get("elapsed_ms", 0))]
			)
		Protocol.Frame.FALSE_START:
			_note("FAUX DEPART piste %d" % int(payload.get("rider", -1)))
		Protocol.Frame.LENGTH_ACK:
			_note("ack longueur : %d ticks" % int(payload.get("ticks", 0)))
		Protocol.Frame.VERSION:
			_note("version : %s" % payload.get("text", ""))
		Protocol.Frame.ERROR, Protocol.Frame.UNKNOWN:
			_note("%s : %s" % [Protocol.frame_name(kind), payload.get("text", "")])
		Protocol.Frame.KIOSK_START, Protocol.Frame.KIOSK_STOP:
			_note("trame kiosque %s (loggee, sans effet)" % Protocol.frame_name(kind))


func _note(text: String) -> void:
	_events.append("[%7.2f s] %s" % [_elapsed, text])


func _process(delta: float) -> bool:
	_elapsed += delta
	# La ligne d'etat n'a pas de retour a la ligne : sans effacement prealable,
	# chaque evenement viendrait s'y coller et deviendrait illisible. Piege deja
	# rencontre sur tools/ss_probe.py — voir tasks/lessons.md.
	if not _events.is_empty():
		printraw("\r%s\r" % " ".repeat(118))
		while not _events.is_empty():
			print(_events.pop_front())

	var circumference := Protocol.circumference_mm(_roller_mm)
	var line := "  %6.2f s " % (_elapsed_ms / 1000.0)
	for i: int in range(Protocol.MAX_RIDERS):
		line += "P%d:%5d t %7.1f m   " % [i, _ticks[i], _ticks[i] * circumference / 1000.0]
	printraw("\r" + line)

	if _duration > 0.0 and _elapsed >= _duration:
		_finish()
		return true
	return false


func _finish() -> void:
	print("")
	print("")
	var stats: Dictionary = _link.get_stats()
	print("statistiques du lien")
	for key: String in stats.keys():
		print("  %-20s %s" % [key, stats[key]])
	_link.stop()
