## Bout en bout SERIE, sur un vrai pseudo-terminal — `docs/06` §2.
##
## La matrice de tests annonce ce niveau depuis le debut : « ouverture de port,
## handshake, threading, watchdog, reconnexion — LA PARTIE RISQUEE ». Rien ne
## l'automatisait. `test_conformite_emulateur.gd` pilote `ss_emu` par `--stdio`
## pour tourner partout, ce qui court-circuite justement la couche serie ; la
## repetition sur pseudo-terminal se faisait a la main, quand on y pensait.
##
## Ici le module natif ouvre un VRAI port, lit des octets a 115200 bauds, remonte
## des trames et arme une course. Le code Godot ne sait pas qu'il ne parle pas a
## un Arduino.
##
## Saute explicitement — jamais vert par absence — la ou le decor manque :
## Windows n'a pas de pseudo-terminal POSIX, l'emulateur n'est pas toujours
## construit, et le module natif pas toujours compile.
extends GutTest

const EMULATOR := "res://build/tools/ss_emu/ss_emu"
const LINK_PATH := "res://.run/ttyTEST"

var _pid := -1
var _link: Link = null


func after_each() -> void:
	if _link != null:
		_link.stop()
		_link.queue_free()
		_link = null
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


## Rend le motif du saut, ou une chaine vide si le decor est complet.
func _missing_decor() -> String:
	if OS.get_name() == "Windows":
		return "Windows n'a pas de pseudo-terminal POSIX"
	if not FileAccess.file_exists(ProjectSettings.globalize_path(EMULATOR)):
		return "ss_emu n'est pas construit ici"
	if not ClassDB.class_exists("SerialLink"):
		return "le module natif n'est pas compile ici"
	return ""


## Lance l'emulateur sur un pseudo-terminal et rend le chemin du lien stable.
func _start_emulator(profile: String) -> String:
	var link_path := ProjectSettings.globalize_path(LINK_PATH)
	DirAccess.make_dir_recursive_absolute(link_path.get_base_dir())
	DirAccess.remove_absolute(link_path)
	_pid = OS.create_process(
		ProjectSettings.globalize_path(EMULATOR),
		["--pty", "--link", link_path, "--riders", "2", "--profile", profile, "--quiet"]
	)
	return link_path


## Laisse a l'emulateur le temps de creer son pseudo-terminal.
##
## PAS de `FileAccess.file_exists` : le lien pointe vers `/dev/pts/N`, un
## fichier de peripherique que Godot ne voit pas comme un fichier ordinaire. Le
## seul signal fiable est l'etat du lien lui-meme, teste plus bas.
func _let_emulator_settle() -> void:
	for i: int in range(120):
		await wait_frames(1)


func _await_state(wanted: int, frames: int = 600) -> bool:
	for i: int in range(frames):
		await wait_frames(1)
		if _link.get_link_state() == wanted:
			return true
	return false


func test_le_module_natif_ouvre_un_vrai_port_et_arme_une_course() -> void:
	var missing := _missing_decor()
	if not missing.is_empty():
		pending("saute : %s" % missing)
		return

	var path := _start_emulator("egaux")
	assert_gt(_pid, 0, "l'emulateur demarre")
	await _let_emulator_settle()

	_link = Link.new()
	add_child_autofree(_link)
	assert_true(_link.use_serial(), "le module natif prend la main")
	_link.set_preferred_port(path)
	_link.start()

	# docs/01 §4 : seul IDENTIFIED autorise le depart, et il exige un `V:` recu.
	assert_true(
		await _await_state(Protocol.State.IDENTIFIED),
		"le boitier repond V: sur un vrai port"
	)
	assert_eq(_link.get_firmware_version(), Protocol.FIRMWARE_VERSION, "et se nomme")
	assert_true(_link.can_start_race(), "le depart devient autorise")

	# Trames collectees a travers la couche serie : decoupage du flux, ring
	# buffer, thread de lecture. C'est tout cela qui est eprouve ici.
	var kinds: Dictionary = {}
	_link.frame_received.connect(
		func(kind: int, _payload: Dictionary) -> void: kinds[kind] = true
	)

	# docs/01 §2 : l'ordre est impose — `d`, puis `l<ticks>`, puis `g`.
	var ticks := Physics.new(Protocol.DEFAULT_ROLLER_MM).metres_to_ticks(100.0)
	assert_true(_link.send_command("d"), "mode distance")
	assert_true(_link.send_command("l%d" % ticks), "longueur")
	assert_true(_link.send_command("g"), "depart")

	for i: int in range(1800):
		await wait_frames(1)
		if kinds.has(Protocol.Frame.PROGRESS) and int(_link.get_stats().get("frames_total", 0)) > 20:
			break
	assert_true(kinds.has(Protocol.Frame.LENGTH_ACK), "le boitier accuse la longueur")
	assert_true(kinds.has(Protocol.Frame.COUNTDOWN), "le decompte arrive")
	assert_true(kinds.has(Protocol.Frame.PROGRESS), "et les trames R: aussi")

	var stats := _link.get_stats()
	assert_gt(int(stats.get("frames_total", 0)), 10, "des trames ont bien traverse")
	assert_eq(int(stats.get("frames_unknown", 0)), 0, "aucune trame incomprise")
	assert_eq(int(stats.get("handshake_failures", 0)), 0, "aucun handshake rate")


func test_le_lien_coupe_est_vu_quand_le_boitier_disparait_en_course() -> void:
	# `docs/01` §6.2 : le watchdog. Il n'est arme QUE pendant une course — hors
	# course, un port silencieux est normal, le boitier n'emet des `R:` qu'en
	# course. Ma premiere version tuait l'emulateur au repos et s'etonnait de
	# rester IDENTIFIED : le lien avait raison, le test avait tort.
	#
	# On arme donc une vraie course, on attend que les trames coulent, PUIS on
	# fait disparaitre le boitier. C'est le cas qu'aucun test ne pouvait
	# produire sans vrai port.
	var missing := _missing_decor()
	if not missing.is_empty():
		pending("saute : %s" % missing)
		return

	var path := _start_emulator("egaux")
	await _let_emulator_settle()
	_link = Link.new()
	add_child_autofree(_link)
	assert_true(_link.use_serial(), "le module natif prend la main")
	_link.set_preferred_port(path)
	_link.start()
	assert_true(await _await_state(Protocol.State.IDENTIFIED), "identifie d'abord")

	var progress: Array[int] = []
	_link.frame_received.connect(
		func(kind: int, _payload: Dictionary) -> void:
			if kind == Protocol.Frame.PROGRESS:
				progress.append(1)
	)
	var ticks := Physics.new(Protocol.DEFAULT_ROLLER_MM).metres_to_ticks(200.0)
	_link.send_command("d")
	_link.send_command("l%d" % ticks)
	_link.send_command("g")
	_link.set_race_active(true)
	for i: int in range(1800):
		await wait_frames(1)
		if progress.size() > 5:
			break
	assert_gt(progress.size(), 5, "la course coule avant qu'on debranche")

	OS.kill(_pid)
	_pid = -1
	var seen := false
	for i: int in range(1800):
		await wait_frames(1)
		var state := _link.get_link_state()
		if state == Protocol.State.LINK_LOST or state == Protocol.State.DISCONNECTED:
			seen = true
			break
	assert_true(seen, "la disparition du boitier en pleine course se voit")
