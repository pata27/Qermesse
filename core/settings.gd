## Reglages persistants — docs/02 §5.
##
## Un reglage absent ou corrompu retombe sur sa valeur par defaut : le logiciel
## doit toujours demarrer. Un fichier de reglages qui empeche de lancer une
## course la veille d'un evenement est pire que pas de reglages du tout.
class_name Settings
extends RefCounted

var preferred_port: String = ""
var use_simulator: bool = true
var roller_mm: float = Physics.DEFAULT_ROLLER_MM
var speed_samples: int = Physics.SPEED_SAMPLES
## Developpement, en metres parcourus par tour de manivelle.
##
## Le capteur compte des tours de ROULEAU : aucun rapport de transmission
## n'intervient (docs/01 §6). La cadence de pedalage est donc INCALCULABLE a
## partir de la mesure seule — elle depend du braquet monte sur le velo.
##
## Ce reglage est la donnee manquante, declaree par l'operateur. Sept metres est
## un developpement courant de piste (48 x 15). Il ne sert QU'A l'affichage de
## la cadence : ni les distances, ni les temps, ni le classement n'en dependent.
var development_m: float = 7.0

var mode: RaceConfig.Mode = RaceConfig.Mode.DISTANCE
var distance_m: float = 500.0
var duration_s: float = 60.0
var gap_m: float = 50.0
var pursuit_time_cap_s: float = 300.0
var pursuit_distance_cap_m: float = 5000.0
var distance_timeout_s: float = 600.0

var false_start_policy: RaceConfig.FalseStartPolicy = RaceConfig.FalseStartPolicy.WARN
var false_start_penalty_m: float = 10.0

## Ecran de destination de la fenetre spectacle — docs/03 §6.
var show_window_screen: int = -1
var single_window_mode: bool = true
## Plein ecran de la fenetre spectacle — INDEPENDANT du fait qu'elle soit
## ouverte. `main.gd` passait `not single_window_mode` comme argument « plein
## ecran » : vouloir la fenetre impliquait le plein ecran, et l'operateur qui
## la gardait en fenetre, pour la surveiller a cote de son panneau, la
## retrouvait plein ecran a chaque lancement. Vrai par defaut : la cible est un
## projecteur. Sous Wayland, le compositeur tranche et ce reglage est inerte.
var spectacle_fullscreen: bool = true
## Coupure audio globale — docs/04 §6.
##
## MUET PAR DEFAUT, et c'est un choix, pas un oubli. En evenementiel la sono est
## presque toujours gerec separement : un logiciel qui se met a sonner par-dessus
## la musique de la salle des la premiere course est un probleme, pas une
## fonctionnalite. L'operateur allume le son quand il a verifie ou il sort.
var audio_muted: bool = true
## Volume general de la bande-son, en decibels. Persiste comme la coupure : le
## manuel fait regler le son LA VEILLE, et un reglage qu'on refait chaque soir
## n'est pas un reglage.
var audio_volume_db: float = 0.0
## Niveau de rendu CHOISI par l'operateur : -1 = detection automatique,
## 0..2 = niveau impose (docs/04 §4, « reglage manuel possible »).
##
## Le choix ne vivait que sur la scene : fermer la fenetre spectacle rendait la
## main a la detection, et la machine du projecteur retrouvait un niveau trop
## lourd a chaque soiree. Un reglage qu'on refait chaque soir n'est pas un
## reglage.
var render_quality: int = -1


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"preferred_port": preferred_port,
		"use_simulator": use_simulator,
		"roller_mm": roller_mm,
		"speed_samples": speed_samples,
		"mode": RaceConfig.mode_name_of(mode),
		"distance_m": distance_m,
		"duration_s": duration_s,
		"gap_m": gap_m,
		"pursuit_time_cap_s": pursuit_time_cap_s,
		"pursuit_distance_cap_m": pursuit_distance_cap_m,
		"distance_timeout_s": distance_timeout_s,
		"false_start_policy": RaceConfig.policy_name(false_start_policy),
		"false_start_penalty_m": false_start_penalty_m,
		"development_m": development_m,
		"show_window_screen": show_window_screen,
		"single_window_mode": single_window_mode,
		"spectacle_fullscreen": spectacle_fullscreen,
		"audio_muted": audio_muted,
		"audio_volume_db": audio_volume_db,
		"render_quality": render_quality,
	}


func from_dict(data: Dictionary) -> void:
	preferred_port = str(data.get("preferred_port", preferred_port))
	use_simulator = bool(data.get("use_simulator", use_simulator))
	roller_mm = _clamp_float(data, "roller_mm", roller_mm, 20.0, 500.0)
	speed_samples = int(clampf(float(data.get("speed_samples", speed_samples)), 1.0, 240.0))
	# NOM OU ENTIER. Les fichiers ecrits par les versions precedentes portent un
	# entier : les refuser perdrait les reglages d'un operateur a la mise a
	# jour. On lit donc les deux, on n'ecrit plus que des noms.
	var raw_mode: Variant = data.get("mode", int(mode))
	mode = (
		RaceConfig.mode_from_name(str(raw_mode), mode) if raw_mode is String
		else _clamp_enum(data, "mode", int(mode), 0, 2) as RaceConfig.Mode
	)
	distance_m = _clamp_float(data, "distance_m", distance_m, 50.0, 5000.0)
	duration_s = _clamp_float(data, "duration_s", duration_s, 10.0, 3600.0)
	gap_m = _clamp_float(data, "gap_m", gap_m, 10.0, 500.0)
	pursuit_time_cap_s = _clamp_float(data, "pursuit_time_cap_s", pursuit_time_cap_s, 10.0, 3600.0)
	pursuit_distance_cap_m = _clamp_float(
		data, "pursuit_distance_cap_m", pursuit_distance_cap_m, 100.0, 100000.0
	)
	distance_timeout_s = _clamp_float(data, "distance_timeout_s", distance_timeout_s, 30.0, 3600.0)
	var raw_policy: Variant = data.get("false_start_policy", int(false_start_policy))
	false_start_policy = (
		RaceConfig.policy_from_name(str(raw_policy), false_start_policy) if raw_policy is String
		else _clamp_enum(data, "false_start_policy", int(false_start_policy), 0, 3)
		as RaceConfig.FalseStartPolicy
	)
	false_start_penalty_m = _clamp_float(data, "false_start_penalty_m", false_start_penalty_m,
		0.0, 500.0)
	development_m = _clamp_float(data, "development_m", development_m, 1.0, 20.0)
	show_window_screen = int(data.get("show_window_screen", show_window_screen))
	single_window_mode = bool(data.get("single_window_mode", single_window_mode))
	spectacle_fullscreen = bool(data.get("spectacle_fullscreen", spectacle_fullscreen))
	audio_muted = bool(data.get("audio_muted", audio_muted))
	# Memes bornes que `RaceAudio.set_volume_db` : rien de ce que l'audio
	# accepte ne doit etre refuse par les reglages.
	audio_volume_db = _clamp_float(data, "audio_volume_db", audio_volume_db, -60.0, 6.0)
	render_quality = _clamp_enum(data, "render_quality", render_quality, -1, 2)


## Construit la configuration de course correspondant aux reglages courants.
func to_race_config(active_riders: Array[int]) -> RaceConfig:
	var config := RaceConfig.new()
	config.mode = mode
	config.active_riders = active_riders
	config.distance_m = distance_m
	config.duration_s = duration_s
	config.gap_m = gap_m
	config.pursuit_time_cap_s = pursuit_time_cap_s
	config.pursuit_distance_cap_m = pursuit_distance_cap_m
	config.distance_timeout_s = distance_timeout_s
	config.false_start_policy = false_start_policy
	config.false_start_penalty_m = false_start_penalty_m
	config.roller_mm = roller_mm
	config.speed_samples = speed_samples
	return config


func save(path: String = "") -> bool:
	return JsonStore.write(path if not path.is_empty() else AppPaths.settings_path(), to_dict())


func load_from(path: String = "") -> bool:
	var data := JsonStore.read(path if not path.is_empty() else AppPaths.settings_path())
	if data.is_empty():
		return false
	from_dict(data)
	return true


## Une valeur hors bornes dans le fichier est ramenee dans les bornes, pas
## rejetee : mieux vaut un reglage plafonne qu'un demarrage refuse.
func _clamp_float(data: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	if not data.has(key):
		return fallback
	return clampf(float(data[key]), low, high)


func _clamp_enum(data: Dictionary, key: String, fallback: int, low: int, high: int) -> int:
	if not data.has(key):
		return fallback
	return int(clampf(float(data[key]), float(low), float(high)))
