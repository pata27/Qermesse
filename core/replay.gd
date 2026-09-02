## Rejeu d'une course enregistree — docs/06 §2.
##
## « Le rejeu est le filet de securite le plus rentable du projet : chaque
## course reelle enregistree en JSON devient un cas de test permanent. Apres le
## premier evenement, on dispose d'une batterie de cas reels que personne
## n'aurait su ecrire a la main. »
##
## Le rejeu ne rejoue PAS un resultat : il repousse les trames brutes dans un
## moteur neuf et recalcule tout. Un rejeu qui relirait le classement enregistre
## ne prouverait rien.
class_name Replay
extends RefCounted


class Loaded:
	extends RefCounted
	var ok: bool = false
	var error: String = ""
	var uuid: String = ""
	var config: RaceConfig = null
	var roster: Dictionary = {}
	var samples: Array = []
	var hardware_finishes: Array = []
	## Classement tel qu'il avait ete enregistre — la reference a retrouver.
	var recorded_ranking: Array[int] = []
	var recorded_elapsed_ms: int = 0
	var recorded_end_reason: int = 0


static func load_file(path: String) -> Loaded:
	var out := Loaded.new()
	if not FileAccess.file_exists(path):
		out.error = "fichier introuvable : %s" % path
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		out.error = "lecture impossible : %s" % path
		return out
	var text := file.get_as_text()
	file.close()
	# Voir json_store.gd : parse() plutot que parse_string(), pour ne pas
	# polluer le journal du moteur sur un cas deja gere.
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		out.error = "JSON invalide : %s" % path
		return out

	var data: Dictionary = json.data
	if str(data.get("format", "")) != "silversprint-race/1":
		out.error = "format inconnu : %s" % str(data.get("format", "(absent)"))
		return out

	var result: Dictionary = data.get("result", {})
	out.uuid = str(data.get("uuid", ""))
	out.config = config_from_dict(data.get("config", {}))
	out.roster = data.get("roster", {})
	out.samples = data.get("samples", [])
	out.hardware_finishes = data.get("hardware_finishes", [])
	# JSON n'a qu'un type numerique : sans cette conversion, le classement relu
	# vaut [0.0, 1.0] et ne sera jamais egal a [0, 1].
	var ranking: Array[int] = []
	for value: Variant in result.get("ranking", []):
		ranking.append(int(value))
	out.recorded_ranking = ranking
	out.recorded_elapsed_ms = int(result.get("elapsed_ms", 0))
	out.recorded_end_reason = int(result.get("end_reason", 0))
	out.ok = true
	return out


## Rejoue les trames dans un moteur NEUF et rend son resultat. Aucun element du
## resultat enregistre n'est reinjecte : c'est tout l'interet.
static func replay(loaded: Loaded) -> RaceResult:
	if not loaded.ok:
		return null
	var engine := RaceEngine.new()
	var produced: Array[RaceResult] = []
	engine.race_finished.connect(func(r: RaceResult) -> void: produced.append(r))

	if not engine.arm(loaded.config, 0):
		return null
	# Le decompte n'influe pas sur l'arbitrage : la premiere trame R: suffit a
	# faire demarrer le moteur (docs/02, la trame fait foi).
	engine.on_countdown(0)

	# Les trames `<idx>F:` sont rejouees A LEUR INSTANT, intercalees dans le
	# flux `R:`. Sans elles, le dernier tick — que le firmware ne transmet
	# jamais, docs/01 §5.6 — manquerait au rejeu, et une course vecue comme
	# terminee resterait un tick sous la cible, indefiniment.
	var finishes: Array = loaded.hardware_finishes.duplicate()
	finishes.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) < int(b[1]))
	var next_finish := 0

	for sample: Variant in loaded.samples:
		var row: Array = sample
		if row.size() < 5:
			continue
		var elapsed_ms := int(row[4])
		while next_finish < finishes.size() and int(finishes[next_finish][1]) < elapsed_ms:
			engine.on_rider_finish(int(finishes[next_finish][0]), int(finishes[next_finish][1]))
			next_finish += 1
		if engine.state() != RaceEngine.State.RUNNING:
			break
		engine.on_progress([int(row[0]), int(row[1]), int(row[2]), int(row[3])], elapsed_ms)
		if engine.state() != RaceEngine.State.RUNNING:
			break
	# Celles qui suivent la derniere `R:` — c'est le cas normal du dernier arrive.
	while next_finish < finishes.size() and engine.state() == RaceEngine.State.RUNNING:
		engine.on_rider_finish(int(finishes[next_finish][0]), int(finishes[next_finish][1]))
		next_finish += 1
	return produced[0] if not produced.is_empty() else null


## Relit le bloc `config` d'un JSON de course — le rejeu et l'historique du
## jour en ont le meme besoin.
static func config_from_dict(raw_config: Dictionary) -> RaceConfig:
	var config := RaceConfig.new()
	config.mode = _mode_from_name(str(raw_config.get("mode", "distance")))
	var riders: Array[int] = []
	for value: Variant in raw_config.get("active_riders", []):
		riders.append(int(value))
	config.active_riders = riders
	config.distance_m = float(raw_config.get("distance_m", 500.0))
	config.duration_s = float(raw_config.get("duration_s", 60.0))
	config.gap_m = float(raw_config.get("gap_m", 50.0))
	config.roller_mm = float(raw_config.get("roller_mm", Physics.DEFAULT_ROLLER_MM))
	config.false_start_policy = raw_config.get("false_start_policy", 1)
	config.pursuit_time_cap_s = float(raw_config.get("pursuit_time_cap_s", 300.0))
	config.pursuit_distance_cap_m = float(raw_config.get("pursuit_distance_cap_m", 5000.0))
	config.distance_timeout_s = float(raw_config.get("distance_timeout_s", 600.0))
	return config


static func _mode_from_name(name: String) -> RaceConfig.Mode:
	match name:
		"temps":
			return RaceConfig.Mode.TIME
		"poursuite":
			return RaceConfig.Mode.PURSUIT
	return RaceConfig.Mode.DISTANCE
