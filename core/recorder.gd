## Persistance des resultats — docs/02 §5.
##
## Deux sorties, deux usages :
##
##   * un CSV cumulatif par journee, en **append reel**. La v1 rechargeait et
##     reecrivait tout le fichier a chaque ligne : au bout d'une soiree, chaque
##     evenement coutait une reecriture complete, et une coupure de courant
##     pendant l'ecriture perdait la journee entiere.
##   * un JSON par course, contenant **la trace complete des trames R:**. C'est
##     le filet de securite le plus rentable du projet : chaque course reelle
##     devient un cas de test permanent, rejouable (docs/06 §2).
##
## Les chemins sont injectes : les tests ecrivent dans un dossier temporaire,
## jamais dans les donnees de l'utilisateur.
class_name Recorder
extends RefCounted

## docs/02 §5 — les cinq evenements que la v1 declarait mais n'ecrivait pas,
## plus les deux ajoutes en v3.
const EVENTS := [
	"RACE_START",
	"FALSE_START",
	"RIDER_FINISH",
	"RIDER_ELIMINATED",
	"TICK_REJECTED",
	"RACE_FINISH",
	"RACE_ABORTED",
	"LINK_LOST",
]

const CSV_HEADER := (
	"timestamp_iso,event,mode,rider,dossard,distance_m,temps_ms,"
	+ "vitesse_moy_kph,vitesse_max_kph,rang,note"
)

var _logs_dir: String
var _races_dir: String
var _csv_path: String = ""
var _problems: Array[String] = []

var _uuid: String = ""
var _config: RaceConfig = null
var _roster: Dictionary = {}
var _started_iso: String = ""
var _samples: Array = []
## Trames `<idx>F:` du boitier, [rider, elapsed_ms]. Elles font partie de la
## trace : sans elles, un rejeu ne verrait jamais le dernier tick (docs/01 §5.6)
## et une course vecue comme terminee ne se terminerait pas rejouee.
var _hardware_finishes: Array = []
var _events: Array[Dictionary] = []
var _last_scan_opened: int = 0


func _init(logs_dir: String = "", races_dir: String = "") -> void:
	_logs_dir = logs_dir if not logs_dir.is_empty() else AppPaths.logs_dir()
	_races_dir = races_dir if not races_dir.is_empty() else AppPaths.races_dir()


func problems() -> Array[String]:
	return _problems


func csv_path() -> String:
	return _csv_path


func current_uuid() -> String:
	return _uuid


## Ouvre une course. `roster` associe un numero de piste a {name, dossard}.
func begin_race(config: RaceConfig, roster: Dictionary = {}) -> String:
	_uuid = _make_uuid()
	# Les problemes sont ceux de CETTE course : une cle USB retiree puis
	# remise ne doit pas faire accuser toutes les courses suivantes.
	_problems.clear()
	_config = config.duplicate_config()
	_roster = roster.duplicate(true)
	_started_iso = Time.get_datetime_string_from_system(true)
	_samples.clear()
	_hardware_finishes.clear()
	_events.clear()
	_append_csv(
		{
			"event": "RACE_START",
			"note": (
				"uuid=%s, %d piste(s) active(s)" % [_uuid, config.active_riders.size()]
			),
		}
	)
	return _uuid


## Trame `R:` retenue. Stockee telle quelle : ticks absolus + horloge firmware,
## exactement ce qu'il faut pour rejouer la course a l'identique.
func record_sample(ticks: PackedInt32Array, elapsed_ms: int) -> void:
	_samples.append([ticks[0], ticks[1], ticks[2], ticks[3], elapsed_ms])


func record_false_start(rider: int) -> void:
	_append_csv({"event": "FALSE_START", "rider": rider})


## Trame `<idx>F:` recue du boitier — observation brute, distincte de l'arrivee
## que le moteur DECIDE (`record_rider_finished`). Les deux vont dans la trace.
func record_hardware_finish(rider: int, elapsed_ms: int) -> void:
	_hardware_finishes.append([rider, elapsed_ms])


func record_rider_finished(rider: int, elapsed_ms: int, rank: int) -> void:
	_append_csv({"event": "RIDER_FINISH", "rider": rider, "temps_ms": elapsed_ms, "rang": rank})


func record_rider_eliminated(rider: int, rank: int, gap_m: float) -> void:
	_append_csv(
		{
			"event": "RIDER_ELIMINATED",
			"rider": rider,
			"rang": rank,
			"note": "ecart %.1f m" % gap_m,
		}
	)


## docs/01 §6.3 : un tick rejete est loggue, jamais silencieusement absorbe.
func record_tick_rejected(rider: int, note: String) -> void:
	_append_csv({"event": "TICK_REJECTED", "rider": rider, "note": note})


func record_link_lost(note: String) -> void:
	_append_csv({"event": "LINK_LOST", "note": note})


func record_abort(note: String) -> void:
	_append_csv({"event": "RACE_ABORTED", "note": note})


## Ecrit une ligne CSV par rider classe, puis le JSON complet de la course.
## Rend le chemin du JSON, ou une chaine vide en cas d'echec.
func finish_race(result: RaceResult) -> String:
	result.uuid = _uuid
	result.started_at_iso = _started_iso
	result.finished_at_iso = Time.get_datetime_string_from_system(true)
	for lane: Variant in _roster:
		result.rider_names[int(lane)] = str((_roster[lane] as Dictionary).get("name", ""))

	for rider: int in result.ranking:
		_append_csv(
			{
				"event": "RACE_FINISH",
				"rider": rider,
				"distance_m": result.distance_m[rider],
				# Le temps COURU — `RaceResult.raced_ms`, la seule definition.
				# Un zero ici pour un elimine ne disait ni quand ni apres combien
				# il avait saute ; pour un survivant de plafond, il disait faux.
				"temps_ms": result.raced_ms(rider),
				"vitesse_moy_kph": result.avg_kph[rider],
				"vitesse_max_kph": result.max_kph[rider],
				"rang": result.rank_of(rider),
				"note": (
					"INTERROMPUE : %s" % result.interruption_note
					if result.interrupted
					else result.end_reason_name()
				),
			}
		)
	return _write_json(result)


func _make_uuid() -> String:
	# Suffisant pour nommer un fichier : horodatage a la milliseconde plus du
	# hasard. Pas de pretention cryptographique.
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	return "%s-%04x" % [stamp.replace("T", "-"), randi() % 0x10000]


func _row_value(row: Dictionary, key: String, fallback: String = "") -> String:
	if not row.has(key):
		return fallback
	var value: Variant = row[key]
	if value is float:
		return "%.3f" % (value as float)
	return str(value)


func _append_csv(row: Dictionary) -> void:
	if not AppPaths.ensure_dir(_logs_dir, _problems):
		return
	_csv_path = _logs_dir.path_join(AppPaths.daily_log_name())

	var is_new := not FileAccess.file_exists(_csv_path)
	# APPEND REEL : on ouvre en lecture-ecriture et on se place a la fin. La v1
	# rechargeait tout le fichier et le reecrivait, ce qui rendait le cout
	# lineaire en nombre de lignes et exposait la journee a une coupure.
	var file := (
		FileAccess.open(_csv_path, FileAccess.WRITE)
		if is_new
		else FileAccess.open(_csv_path, FileAccess.READ_WRITE)
	)
	if file == null:
		_problems.append(
			"ecriture CSV impossible : %s (%d)" % [_csv_path, FileAccess.get_open_error()]
		)
		return
	if is_new:
		file.store_line(CSV_HEADER)
	else:
		file.seek_end()

	var rider: int = int(row.get("rider", -1))
	var dossard := ""
	if rider >= 0 and _roster.has(rider):
		dossard = str((_roster[rider] as Dictionary).get("dossard", ""))

	var fields := [
		Time.get_datetime_string_from_system(true),
		_row_value(row, "event"),
		_config.mode_name() if _config != null else "",
		str(rider) if rider >= 0 else "",
		dossard,
		_row_value(row, "distance_m"),
		_row_value(row, "temps_ms"),
		_row_value(row, "vitesse_moy_kph"),
		_row_value(row, "vitesse_max_kph"),
		_row_value(row, "rang"),
		_escape_csv(_row_value(row, "note")),
	]
	file.store_line(",".join(fields))
	file.close()


## Une note peut contenir une virgule. Sans echappement, la colonne suivante
## se decale et le CSV devient faux sans prevenir.
## Relit les courses du jour depuis leurs JSON — docs/02 §5, « Historique du
## jour ». Le jour est le jour LOCAL, celui qui nomme le CSV ; `started_at` est
## ecrit en UTC, d'ou la conversion. Un fichier illisible ou d'un autre format
## est ignore en silence : l'historique ne doit jamais empecher de courir.
func load_day(now: Dictionary = Time.get_datetime_dict_from_system()) -> Array[RaceResult]:
	var found: Array[RaceResult] = []
	if not DirAccess.dir_exists_absolute(_races_dir):
		return found
	var bias_s := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	# Le nom du fichier est horodate en UTC (`_make_uuid`) : un jour local
	# ne recouvre que deux dates UTC au plus. Tout autre fichier est ecarte
	# SANS etre ouvert — le dossier ne s'elague jamais, chaque fichier pese
	# des centaines de Ko de trace.
	var local_midnight := Time.get_unix_time_from_datetime_dict(
		{"year": now["year"], "month": now["month"], "day": now["day"],
		"hour": 0, "minute": 0, "second": 0}
	)
	var candidates: PackedStringArray = []
	for local_unix: int in [local_midnight, local_midnight + 24 * 3600 - 1]:
		var utc := Time.get_datetime_dict_from_unix_time(local_unix - bias_s)
		candidates.append("%04d%02d%02d" % [utc["year"], utc["month"], utc["day"]])
	_last_scan_opened = 0
	for name: String in DirAccess.get_files_at(_races_dir):
		if name.get_extension() != "json" or not candidates.has(name.substr(0, 8)):
			continue
		_last_scan_opened += 1
		var data := JsonStore.read(_races_dir.path_join(name))
		if data.is_empty() or str(data.get("format", "")) != "silversprint-race/1":
			continue
		var started := str(data.get("started_at", ""))
		if not _is_same_local_day(started, bias_s, now):
			continue
		found.append(RaceResult.from_json(data))
	# `started_at` est a la seconde : deux courses dans la meme seconde n'existent
	# qu'en test, mais l'ordre doit rester deterministe — l'uuid tranche.
	found.sort_custom(
		func(a: RaceResult, b: RaceResult) -> bool:
			if a.started_at_iso != b.started_at_iso:
				return a.started_at_iso < b.started_at_iso
			return a.uuid < b.uuid
	)
	return found


## Fichiers ouverts par le dernier `load_day` — pour prouver que le filtre
## sur le nom travaille avant le parseur.
func last_scan_opened() -> int:
	return _last_scan_opened


static func _is_same_local_day(started_utc_iso: String, bias_s: int, now: Dictionary) -> bool:
	# Une date malformee vaut 0 (1970) : jamais « aujourd'hui ».
	if started_utc_iso.length() < 19:
		return false
	var unix := Time.get_unix_time_from_datetime_string(started_utc_iso)
	if unix <= 0:
		return false
	var local := Time.get_datetime_dict_from_unix_time(unix + bias_s)
	return (
		int(local["year"]) == int(now["year"])
		and int(local["month"]) == int(now["month"])
		and int(local["day"]) == int(now["day"])
	)


func _escape_csv(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


func _write_json(result: RaceResult) -> String:
	if not AppPaths.ensure_dir(_races_dir, _problems):
		return ""
	var path := _races_dir.path_join("%s.json" % _uuid)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_problems.append("ecriture JSON impossible : %s" % path)
		return ""

	var payload := {
		"format": "silversprint-race/1",
		"uuid": _uuid,
		"started_at": _started_iso,
		"finished_at": result.finished_at_iso,
		"firmware": Protocol.FIRMWARE_VERSION,
		"config": {
			"mode": result.mode,
			"active_riders": _config.active_riders,
			"distance_m": _config.distance_m,
			"duration_s": _config.duration_s,
			"gap_m": _config.gap_m,
			"roller_mm": _config.roller_mm,
			"false_start_policy": int(_config.false_start_policy),
			"pursuit_time_cap_s": _config.pursuit_time_cap_s,
			"pursuit_distance_cap_m": _config.pursuit_distance_cap_m,
			"distance_timeout_s": _config.distance_timeout_s,
		},
		"roster": _roster,
		"result": {
			"ranking": result.ranking,
			"elapsed_ms": result.elapsed_ms,
			"end_reason": int(result.end_reason),
			"interrupted": result.interrupted,
			"interruption_note": result.interruption_note,
			"finished_ms": Array(result.finished_ms),
			"eliminated_ms": Array(result.eliminated_ms),
			"distance_m": Array(result.distance_m),
			"avg_kph": Array(result.avg_kph),
			"max_kph": Array(result.max_kph),
			"eliminated": result.eliminated,
			"false_started": result.false_started,
		},
		# La trace complete : [t0, t1, t2, t3, elapsed_ms] par trame retenue.
		# ~100 Hz x 60 s = 6000 echantillons, quelques centaines de Ko.
		"samples": _samples,
		"hardware_finishes": _hardware_finishes,
	}
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return path
