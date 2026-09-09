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

## Course de DÉMONSTRATION : rien ne part au disque.
##
## Le mode démo fait courir des coureurs synthétiques pour occuper l'écran quand
## personne ne pédale. Ces courses n'ont pas eu lieu : les laisser atterrir dans
## « Courses du jour », dans le journal du jour et dans le dossier des courses
## rendrait la soirée de l'opérateur illisible — et un doute sur ce qui a
## réellement été couru est un doute sur TOUT le fichier.
##
## LE SILENCE EST POSÉ ICI, sur les deux seules portes de sortie vers le disque,
## et non chez les appelants. Le contrôleur écrit à sept endroits différents ;
## un seul `if` oublié suffirait à polluer le fichier de la journée, et
## personne ne s'en apercevrait avant de le relire.
var muted := false

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
## Fichiers du jour que le dernier `load_day` n'a pas su relire. Les compter ne
## coute rien et evite le pire : une liste incomplete qu'on croit complete.
var _last_scan_unreadable: Array[String] = []


func _init(logs_dir: String = "", races_dir: String = "") -> void:
	_logs_dir = logs_dir if not logs_dir.is_empty() else AppPaths.logs_dir()
	_races_dir = races_dir if not races_dir.is_empty() else AppPaths.races_dir()


func problems() -> Array[String]:
	return _problems


## Dossier des courses, et chemin du JSON d'une course donnee. `DEPANNAGE`
## demande a l'operateur d'envoyer ce fichier au developpeur : encore faut-il
## qu'il puisse le nommer sans deviner un dossier voisin et un uuid.
func races_dir() -> String:
	return _races_dir


func json_path(uuid: String) -> String:
	return "" if uuid.is_empty() else _races_dir.path_join("%s.json" % uuid)


## Le journal CSV de la course OUVERTE — ou, hors course, celui ou ira la
## prochaine : le fichier du jour. Il restait vide jusqu'a la premiere ligne
## ecrite, si bien que le panneau Resultats affichait « CSV : » sans chemin au
## lancement — alors que le manuel fait reperer ce chemin LA VEILLE, dans une
## salle vide, avant toute course.
func csv_path() -> String:
	if _csv_path.is_empty():
		return _logs_dir.path_join(AppPaths.daily_log_name())
	return _csv_path


## Ouvre une course. `roster` associe un numero de piste a {name, dossard}.
## `now` s'injecte pour les tests ; en soiree c'est l'horloge de la machine.
func begin_race(
	config: RaceConfig, roster: Dictionary = {},
	now: Dictionary = Time.get_datetime_dict_from_system()
) -> String:
	_uuid = _make_uuid()
	# LE JOURNAL DU JOUR EST CHOISI UNE FOIS PAR COURSE, ici. Chaque ligne le
	# recalculait a l'horloge du moment : une course a cheval sur la bascule de
	# 5 h du matin ecrivait son depart dans le fichier de la veille et son
	# arrivee dans celui du lendemain — coupee en deux, et introuvable en entier
	# dans l'un comme dans l'autre. Son JSON, lui, est range au jour du DEPART
	# (`load_day` lit `started_at`) : le CSV suit desormais la meme regle, et une
	# course n'a plus deux jours.
	_csv_path = _logs_dir.path_join(AppPaths.daily_log_name(now))
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


## Trame `R:` BRUTE, telle que le boitier l'a envoyee — avant le filtre et avant
## le gel d'un rider arrive. Ticks absolus et horloge firmware : de quoi rejouer
## la course a l'identique, ET de quoi voir ce que le filtre a refuse. Stocker
## les valeurs retenues faisait disparaitre le tick rejete du fichier meme que
## `DEPANNAGE` fait envoyer pour diagnostiquer ce rejet.
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
			"note": "écart %.1f m" % gap_m,
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
		var entry: Dictionary = _roster[lane]
		result.rider_names[int(lane)] = str(entry.get("name", ""))
		result.rider_dossards[int(lane)] = str(entry.get("dossard", ""))

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
				# LA NOTE DECRIT CE RIDER, pas la course. Un elimine a 14 s
				# portait « dernier en course » — le motif de fin de LA COURSE,
				# faux de lui. Dans un tableur chaque ligne se lit seule.
				#
				# Une course decidee au plafond porte son motif de fin, pas le
				# mot « interrompue » : seul un ARRET n'a pas de vainqueur
				# (docs/02 §3).
				"note": _finish_note(result, rider),
			}
		)
	return _write_json(result)


## Note de la ligne `RACE_FINISH` d'un rider.
##
## Elle DECRIT CE RIDER, pas la course : dans un tableur, chaque ligne se lit
## seule. Un elimine porte l'instant de sa sortie, un survivant d'arret porte le
## motif, et un ex aequo porte « photo-finish » — sans quoi deux temps
## identiques avec les rangs 1 et 2 se relisaient six mois plus tard comme une
## coincidence d'arrondi. L'ecran public et le tableau operateur le disaient
## deja ; le fichier qui survit a la soiree, non.
static func _finish_note(result: RaceResult, rider: int) -> String:
	var note := ""
	if result.eliminated[rider]:
		note = (
			"éliminé à %.2f s" % (result.eliminated_ms[rider] / 1000.0)
			if result.eliminated_ms[rider] > 0
			else "éliminé"
		)
	elif result.was_stopped():
		note = "INTERROMPUE : %s" % result.interruption_note
	else:
		note = result.end_reason_name()
	if result.is_dead_heat(rider):
		note += " — photo-finish, départagé par le numéro de piste"
	return note


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
	if muted:
		return
	if not AppPaths.ensure_dir(_logs_dir, _problems):
		return
	# Le chemin a ete fixe par `begin_race` ; on ne le recalcule que s'il manque —
	# un appel hors course, qui n'existe pas aujourd'hui mais qu'on ne veut pas
	# voir echouer en silence.
	if _csv_path.is_empty():
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
			"écriture CSV impossible : %s (%d)" % [_csv_path, FileAccess.get_open_error()]
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
		_local_stamp(),
		_row_value(row, "event"),
		_config.mode_name() if _config != null else "",
		str(rider) if rider >= 0 else "",
		dossard,
		_row_value(row, "distance_m"),
		_row_value(row, "temps_ms"),
		_row_value(row, "vitesse_moy_kph"),
		_row_value(row, "vitesse_max_kph"),
		_row_value(row, "rang"),
		_row_value(row, "note"),
	]
	# ECHAPPEMENT DE TOUTE LA LIGNE, pas du seul champ « note ».
	#
	# Il ne portait que sur la note, parce que c'est la qu'on attendait une
	# virgule. Mais le DOSSARD est un champ de texte libre saisi par
	# l'operateur : « 7,5 » suffisait a produire une ligne de douze colonnes
	# dans un fichier qui en annonce onze, et tout ce qui suit se decalait — la
	# distance devenait un morceau du dossard, le temps devenait la distance.
	# Silencieux, et sur le fichier meme que `DEPANNAGE` fait envoyer au
	# developpeur devant un resultat suspect.
	#
	# Echapper a la sortie plutot qu'a chaque champ : c'est le seul endroit ou
	# une ligne devient du CSV, et un champ ajoute plus tard y passera sans que
	# personne ait a y penser.
	var safe := PackedStringArray()
	for field: Variant in fields:
		safe.append(_escape_csv(str(field)))
	file.store_line(",".join(safe))
	file.close()


## Une note peut contenir une virgule. Sans echappement, la colonne suivante
## se decale et le CSV devient faux sans prevenir.
## Relit les courses du jour depuis leurs JSON — docs/02 §5, « Historique du
## jour ». Le jour est le jour LOCAL, celui qui nomme le CSV ; `started_at` est
## ecrit en UTC, d'ou la conversion.
##
## Un fichier illisible ou d'un autre format est ECARTE mais COMPTE. L'historique
## ne doit jamais empecher de courir — c'est pourquoi rien n'echoue ici — mais le
## silence allait trop loin : une course disparaissait de « Courses du jour »
## sans un mot, et l'operateur se retrouvait le soir avec onze lignes pour douze
## manches courues, sans savoir laquelle manquait ni pourquoi. Or c'est
## precisement ce fichier que `DEPANNAGE` lui fait envoyer au developpeur devant
## un resultat suspect : qu'il soit illisible est une nouvelle, pas un detail.
func load_day(now: Dictionary = Time.get_datetime_dict_from_system()) -> Array[RaceResult]:
	var found: Array[RaceResult] = []
	if not DirAccess.dir_exists_absolute(_races_dir):
		return found
	var bias_s := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	# Le nom du fichier est horodate en UTC (`_make_uuid`) : un jour local
	# ne recouvre que deux dates UTC au plus. Tout autre fichier est ecarte
	# SANS etre ouvert — le dossier ne s'elague jamais, chaque fichier pese
	# des centaines de Ko de trace.
	# La fenetre va de 5 h a 5 h le lendemain (docs/02 §5). Comme toute plage de
	# vingt-quatre heures, elle touche au plus deux dates UTC — mais ce ne sont
	# plus les memes qu'avec un decoupage a minuit, d'ou le recalcul.
	var day := AppPaths.operating_day(now)
	var window_start := Time.get_unix_time_from_datetime_dict(
		{"year": day["year"], "month": day["month"], "day": day["day"],
		"hour": AppPaths.DAY_ROLLOVER_HOUR, "minute": 0, "second": 0}
	)
	var candidates: PackedStringArray = []
	for local_unix: int in [window_start, window_start + 24 * 3600 - 1]:
		var utc := Time.get_datetime_dict_from_unix_time(local_unix - bias_s)
		var stamp := "%04d%02d%02d" % [utc["year"], utc["month"], utc["day"]]
		if not candidates.has(stamp):
			candidates.append(stamp)
	_last_scan_opened = 0
	_last_scan_unreadable.clear()
	for name: String in DirAccess.get_files_at(_races_dir):
		if name.get_extension() != "json" or not candidates.has(name.substr(0, 8)):
			continue
		_last_scan_opened += 1
		var data := JsonStore.read(_races_dir.path_join(name))
		if data.is_empty() or str(data.get("format", "")) != "silversprint-race/1":
			# Le nom du fichier porte deja la date du jour — le filtre au-dessus
			# l'a verifie — donc c'est bien une course d'aujourd'hui qui manque.
			_last_scan_unreadable.append(name)
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
## Noms des fichiers du jour que le dernier `load_day` a du ecarter.
func last_scan_unreadable() -> Array[String]:
	return _last_scan_unreadable


func last_scan_opened() -> int:
	return _last_scan_opened


static func _is_same_local_day(started_utc_iso: String, bias_s: int, now: Dictionary) -> bool:
	# Une date malformee vaut 0 (1970) : jamais « aujourd'hui ».
	if started_utc_iso.length() < 19:
		return false
	var unix := Time.get_unix_time_from_datetime_string(started_utc_iso)
	if unix <= 0:
		return false
	# La JOURNEE D'EXPLOITATION, pas la journee du calendrier : on compare les
	# deux dates apres avoir recule de l'heure de bascule (docs/02 §5).
	var started := AppPaths.operating_day(
		Time.get_datetime_dict_from_unix_time(unix + bias_s)
	)
	var today := AppPaths.operating_day(now)
	return (
		int(started["year"]) == int(today["year"])
		and int(started["month"]) == int(today["month"])
		and int(started["day"]) == int(today["day"])
	)


## Horodatage ISO 8601 COMPLET : heure locale ET decalage explicite,
## `2026-09-02T22:49:00+02:00`.
##
## Le CSV est le fichier que l'operateur ouvre dans un tableur ; il est nomme
## par le jour LOCAL. Sa colonne etait en UTC : deux heures d'ecart a la
## lecture, et une course de fin de soiree portant la date de la veille. Le
## decalage est ecrit plutot que sous-entendu — un horodatage sans fuseau ne
## veut rien dire des qu'il change de machine.
##
## Le JSON de course, lui, reste en UTC : c'est un artefact machine, relu par
## l'historique du jour qui fait la conversion (docs/02 §5).
static func _local_stamp() -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var local := Time.get_datetime_string_from_unix_time(
		int(Time.get_unix_time_from_system()) + bias * 60
	)
	var minutes := absi(bias)
	return "%s%s%02d:%02d" % [local, "+" if bias >= 0 else "-", minutes / 60, minutes % 60]


func _escape_csv(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


func _write_json(result: RaceResult) -> String:
	if muted:
		return ""
	if not AppPaths.ensure_dir(_races_dir, _problems):
		return ""
	var path := _races_dir.path_join("%s.json" % _uuid)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_problems.append("écriture JSON impossible : %s" % path)
		return ""

	var payload := {
		"format": "silversprint-race/1",
		"uuid": _uuid,
		"started_at": _started_iso,
		"finished_at": result.finished_at_iso,
		"firmware": Protocol.FIRMWARE_VERSION,
		"app": AppVersion.current(),
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
			# TOUT CE QUI A ARBITRE LA COURSE. Deux champs manquaient — la
			# penalite de faux depart et la fenetre de lissage — et le rejeu
			# les prenait par defaut : une course a 25 m de penalite se
			# rejouait a 10 m, et l'outil accusait d'ecart une trace saine.
			# `test_recorder` compare cette liste aux champs declares.
			"false_start_penalty_m": _config.false_start_penalty_m,
			"speed_samples": _config.speed_samples,
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
