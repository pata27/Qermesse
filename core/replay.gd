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
	## Course arretee avant son terme, et pourquoi — docs/02 §5.
	## Le nom de mode tel qu'il est ECRIT dans le fichier. `mode_from_name`
	## retombe sur « distance » pour un nom inconnu : sans garder l'original, un
	## fichier edite a la main se rejouerait avec la mauvaise regle, et la
	## divergence constatee accuserait la course au lieu du fichier.
	var recorded_mode_name: String = ""
	var recorded_interrupted: bool = false
	var recorded_interruption_note: String = ""
	## Les CHIFFRES enregistres, par piste : temps d'arrivee, distance, moyenne,
	## pointe. Le rejeu les recalcule tous ; sans les avoir sous la main, il ne
	## pouvait comparer que l'ordre d'arrivee.
	## La trace porte-t-elle tout ce qu'il faut pour comparer ses CHIFFRES ?
	## `eliminated_ms` n'existe que depuis que le moteur retient l'instant d'une
	## elimination ; sans lui, les moyennes du fichier ont ete calculees sur
	## toute la course et aucun moteur d'aujourd'hui ne les redonnera.
	var recorded_complete: bool = false
	var recorded_finished_ms: Array[int] = []
	var recorded_distance_m: Array[float] = []
	var recorded_avg_kph: Array[float] = []
	var recorded_max_kph: Array[float] = []


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
	out.recorded_mode_name = str(data.get("config", {}).get("mode", ""))
	out.recorded_interrupted = bool(result.get("interrupted", false))
	out.recorded_interruption_note = str(result.get("interruption_note", ""))
	for rider: int in range(Protocol.MAX_RIDERS):
		out.recorded_finished_ms.append(int(_nth(result.get("finished_ms", []), rider, 0)))
		out.recorded_distance_m.append(float(_nth(result.get("distance_m", []), rider, 0.0)))
		out.recorded_avg_kph.append(float(_nth(result.get("avg_kph", []), rider, 0.0)))
		out.recorded_max_kph.append(float(_nth(result.get("max_kph", []), rider, 0.0)))
	out.recorded_complete = result.has("eliminated_ms")
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

	# LA TRACE S'ARRETE SANS QUE LA COURSE SE TERMINE : elle a ete interrompue.
	# On l'interrompt de la meme facon plutot que de rendre `null` — sinon le
	# fichier le plus utile apres un incident serait le seul inexploitable.
	if engine.state() == RaceEngine.State.RUNNING and loaded.recorded_interrupted:
		engine.abort(loaded.recorded_interruption_note)
		return engine.result()
	return produced[0] if not produced.is_empty() else null


## Relit le bloc `config` d'un JSON de course — le rejeu et l'historique du
## jour en ont le meme besoin.
static func config_from_dict(raw_config: Dictionary) -> RaceConfig:
	var config := RaceConfig.new()
	config.mode = RaceConfig.mode_from_name(str(raw_config.get("mode", "distance")))
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
	# Absents des traces anterieures : les defauts d'alors, qui etaient aussi
	# ceux que le rejeu prenait en silence.
	config.false_start_penalty_m = float(raw_config.get("false_start_penalty_m", 10.0))
	config.speed_samples = int(raw_config.get("speed_samples", Physics.SPEED_SAMPLES))
	return config


## Nieme valeur d'un tableau relu du JSON, ou un defaut. Une trace tronquee ou
## d'une version anterieure n'a pas toujours quatre entrees.
static func _nth(values: Variant, index: int, fallback: Variant) -> Variant:
	var list: Array = values if values is Array else []
	return list[index] if index >= 0 and index < list.size() else fallback


## Ecarts entre les chiffres RECALCULES et ceux enregistres, un par ligne.
##
## RIEN N'EST COMPARE SUR UNE TRACE ANCIENNE, et le motif est dit. Les traces de
## reference du depot ont ete enregistrees AVANT que le moteur ne connaisse
## l'instant d'elimination : leurs moyennes d'elimines sont calculees sur toute
## la course, et le moteur d'aujourd'hui ne les redonnera jamais. Leur
## anciennete est precisement leur valeur — voir `tests/fixtures/LISEZMOI.md` —
## et les declarer divergentes reviendrait a leur reprocher d'etre ce qu'elles
## sont. L'absence d'`eliminated_ms` dans le fichier est le signe de cette
## anciennete.
##
## Le rejeu repousse les memes trames dans un moteur neuf : le calcul est
## deterministe, et les deux series doivent coincider. Les tolerances ne
## couvrent que l'aller-retour par le JSON, ou les flottants sont ecrits en
## decimal — pas une difference de calcul, qui est justement ce qu'on cherche.
static func figure_gaps(loaded: Loaded, replayed: RaceResult) -> Array[String]:
	var gaps: Array[String] = []
	if not loaded.recorded_complete:
		return gaps
	for rider: int in replayed.ranking:
		if rider < 0 or rider >= loaded.recorded_distance_m.size():
			continue
		var checks := [
			["temps", float(replayed.finished_ms[rider]),
				float(loaded.recorded_finished_ms[rider]), 2.0, "ms"],
			["distance", replayed.distance_m[rider],
				loaded.recorded_distance_m[rider], 0.05, "m"],
			["moyenne", replayed.avg_kph[rider],
				loaded.recorded_avg_kph[rider], 0.1, "km/h"],
			["pointe", replayed.max_kph[rider],
				loaded.recorded_max_kph[rider], 0.1, "km/h"],
		]
		for check: Array in checks:
			var rejoue: float = check[1]
			var ecrit: float = check[2]
			if absf(rejoue - ecrit) <= float(check[3]):
				continue
			gaps.append(
				"piste %d, %s : rejoue %.2f %s, enregistre %.2f %s"
				% [rider + 1, check[0], rejoue, check[4], ecrit, check[4]]
			)
	return gaps
