## Conformité `link_sim.gd` ↔ `ss_emu` — docs/03 §5 et docs/07 §8.
##
## « `link_sim.gd` produit exactement les mêmes trames que `ss_emu`, mêmes bugs
## compris. Toute divergence entre les deux est un bug de `link_sim.gd`. »
##
## Les deux simulateurs sont deux implémentations séparées — GDScript en
## processus, C++ sur un flux d'octets. Ce test les fait courir sur le MÊME
## scénario à graine fixée et compare ce qui doit être identique : la suite des
## trames événementielles, les compteurs de ticks à l'arrivée, l'ordre
## d'arrivée, et le bug de la dernière trame `R:` — qui doit être reproduit des
## deux côtés, puisque le vrai firmware l'a.
##
## `ss_emu` est piloté par `--stdio` : aucun pseudo-terminal, donc le test tourne
## partout où le binaire existe. Là où il n'est pas construit, le test est
## sauté explicitement — jamais vert par absence.
extends GutTest

const SIM := preload("res://hardware/link_sim.gd")
const EMU := "res://build/tools/ss_emu/ss_emu"
const SEED := 7
const RIDERS := 2
const LENGTH_TICKS := 278  # 100 m au rouleau de 114,3 mm

var _sim_lines := PackedStringArray()


func _emulator_binary() -> String:
	var path := ProjectSettings.globalize_path(EMU)
	return path if FileAccess.file_exists(path) else ""


## Fait courir `ss_emu` sur le scénario et rend ses lignes.
##
## L'émulateur ne se termine pas sur la fin de l'entrée — comme un vrai port
## série, il attend toujours — d'où `timeout`. Sa sortie d'erreur est son
## tableau de bord, qu'on jette.
func _run_emulator(binary: String) -> PackedStringArray:
	var script := (
		"( printf 'v\\n'; sleep 0.4; printf 'd\\n'; sleep 0.1; printf 'l%d\\n'; sleep 0.1; "
		+ "printf 'g\\n'; sleep 1.6 ) | timeout 5 %s --stdio --seed %d --riders %d "
		+ "--profile egaux --speed 20 2>/dev/null"
	) % [LENGTH_TICKS, binary, SEED, RIDERS]
	var output: Array = []
	OS.execute("bash", ["-c", script], output, true)
	return (output[0] as String).split("\n", false)


## Fait courir `link_sim` sur le même scénario et rend ses trames au même format
## texte que le firmware — c'est la seule façon de comparer les deux.
func _run_link_sim() -> PackedStringArray:
	_sim_lines = PackedStringArray()
	var sim: Node = SIM.new()
	sim.wired_riders = RIDERS
	sim.seed = SEED
	sim.profile = "egaux"
	# Méthode nommée plutôt que lambda : le parseur refuse un `match` sur des
	# motifs d'enum à l'intérieur d'une lambda.
	sim.frame_received.connect(_on_sim_frame)
	sim.start()
	# PAS de `v` explicite ici, alors qu'on en envoie un à `ss_emu`.
	#
	# Les deux simulateurs ne sont pas au même niveau (docs/07 §8) : `ss_emu`
	# sur `--stdio` est un firmware NU, sans pilote devant lui — c'est nous qui
	# faisons la poignée de main, d'où le `v`. `link_sim`, lui, vit derrière la
	# façade `link.gd` et intègre cette poignée de main : son `V:` à la
	# connexion EST le `v` du pilote. Lui en envoyer un second comparerait un
	# firmware qui a reçu deux `v` à un firmware qui n'en a reçu qu'un — et
	# c'est ce que la première version de ce test faisait, accusant à tort
	# le simulateur d'une divergence.
	for i: int in range(80):
		sim.advance(0.01)
	sim.send_command("d")
	sim.send_command("l%d" % LENGTH_TICKS)
	sim.send_command("g")
	# Vingt secondes simulées : le décompte, la course à 45 km/h sur 100 m, et
	# de la marge pour que le second franchisse.
	for i: int in range(2000):
		sim.advance(0.01)
	sim.free()
	return _sim_lines


## Transcrit une trame de `link_sim` au format texte du firmware.
func _on_sim_frame(kind: int, payload: Dictionary) -> void:
	match kind:
		Protocol.Frame.VERSION:
			_sim_lines.append("V:%s" % payload["text"])
		Protocol.Frame.LENGTH_ACK:
			_sim_lines.append("L:%d" % int(payload["ticks"]))
		Protocol.Frame.COUNTDOWN:
			_sim_lines.append("CD:%d" % int(payload["value"]))
		Protocol.Frame.RIDER_FINISH:
			_sim_lines.append("%dF:%d" % [int(payload["rider"]), int(payload["elapsed_ms"])])
		Protocol.Frame.PROGRESS:
			var ticks: Array = payload["ticks"]
			_sim_lines.append("R:%d,%d,%d,%d,%d" % [
				int(ticks[0]), int(ticks[1]), int(ticks[2]), int(ticks[3]),
				int(payload["elapsed_ms"])])


## Ne garde que les trames ÉVÉNEMENTIELLES, sans leurs horodatages : c'est la
## structure de la course qu'on compare, pas la milliseconde.
static func _events(lines: PackedStringArray) -> PackedStringArray:
	var events := PackedStringArray()
	for line: String in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("V:") or trimmed.begins_with("L:") or trimmed.begins_with("CD:"):
			events.append(trimmed)
		elif trimmed.length() > 2 and trimmed.substr(1, 2) == "F:":
			events.append(trimmed.substr(0, 3))
	return events


## Ticks des deux coureurs dans la dernière `R:` émise AVANT le premier `F:`.
static func _ticks_before_first_finish(lines: PackedStringArray) -> Array:
	var last_r := ""
	for line: String in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("R:"):
			last_r = trimmed
		elif trimmed.length() > 2 and trimmed.substr(1, 2) == "F:":
			break
	if last_r.is_empty():
		return []
	var fields := last_r.substr(2).split(",")
	return [int(fields[0]), int(fields[1])]


static func _finish_ms(lines: PackedStringArray, rider: int) -> int:
	var prefix := "%dF:" % rider
	for line: String in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with(prefix):
			return int(trimmed.substr(3))
	return -1


func test_link_sim_produit_la_meme_suite_de_trames_que_ss_emu() -> void:
	var binary := _emulator_binary()
	if binary.is_empty():
		pending("ss_emu n'est pas construit ici — vérifié là où il l'est (CI POSIX)")
		return

	var emu := _run_emulator(binary)
	var sim := _run_link_sim()
	assert_gt(emu.size(), 100, "l'émulateur a bien couru")
	assert_gt(sim.size(), 100, "link_sim a bien couru")

	# 1. La même suite d'événements, dans le même ordre.
	assert_eq(
		_events(sim), _events(emu),
		"V, L, CD:3→0, puis les arrivées, dans le même ordre"
	)

	# 2. Le même bug de dernière trame, DES DEUX CÔTÉS : la valeur qui atteint la
	#    cible n'est jamais transmise (docs/01 §5.6, ss_basic.ino l. 285-307).
	var emu_ticks := _ticks_before_first_finish(emu)
	var sim_ticks := _ticks_before_first_finish(sim)
	assert_eq(sim_ticks, emu_ticks, "mêmes compteurs dans la dernière R: avant l'arrivée")
	assert_lt(int(emu_ticks[0]), LENGTH_TICKS, "ss_emu : la cible n'est jamais dans une R:")
	assert_lt(int(sim_ticks[0]), LENGTH_TICKS, "link_sim : la cible n'est jamais dans une R:")

	# 3. Les mêmes temps d'arrivée, à la trame près. Les deux pas de simulation
	#    valent dix millisecondes ; au-delà d'une trame d'écart, les modèles de
	#    coureur ont divergé et c'est un bug de link_sim.
	for rider: int in range(RIDERS):
		var emu_ms := _finish_ms(emu, rider)
		var sim_ms := _finish_ms(sim, rider)
		assert_gt(emu_ms, 0, "ss_emu : piste %d arrivée" % (rider + 1))
		assert_gt(sim_ms, 0, "link_sim : piste %d arrivée" % (rider + 1))
		assert_almost_eq(
			float(sim_ms), float(emu_ms), 20.0,
			"piste %d : même temps d'arrivée à deux trames près" % (rider + 1)
		)
