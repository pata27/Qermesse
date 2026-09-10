## Emplacements des donnees, par systeme — docs/02 §5.
##
## Godot expose `user://`, mais son emplacement par defaut
## (`~/.local/share/godot/app_userdata/...`) n'est pas celui que la spec impose
## et serait introuvable pour un operateur qui cherche son CSV. On resout donc
## les chemins explicitement.
##
##   Linux    ~/.config/qermesse/  et  ~/.local/share/qermesse/
##   macOS    ~/Library/Application Support/Qermesse/
##   Windows  %APPDATA%\Qermesse\
class_name AppPaths
extends RefCounted

const APP_NAME_UNIX := "qermesse"
const APP_NAME_OTHER := "Qermesse"
## Heure locale a laquelle bascule la journee d'exploitation — docs/02 §5.
const DAY_ROLLOVER_HOUR := 5


static func app_folder() -> String:
	# Convention Linux : minuscules dans ~/.config. macOS et Windows utilisent
	# le nom affiche.
	return APP_NAME_UNIX if OS.get_name() == "Linux" else APP_NAME_OTHER


static func config_dir() -> String:
	return OS.get_config_dir().path_join(app_folder())


static func data_dir() -> String:
	return OS.get_data_dir().path_join(app_folder())


static func settings_path() -> String:
	return config_dir().path_join("settings.json")


static func roster_path() -> String:
	return config_dir().path_join("roster.json")


## CSV cumulatif de la journee — docs/02 §5.
static func logs_dir() -> String:
	return data_dir().path_join("logs")


## Un fichier JSON par course, avec la trace complete des trames.
static func races_dir() -> String:
	return data_dir().path_join("races")


## Date de la journee d'exploitation qui contient `now` — docs/02 §5.
##
## Une soiree de goldsprints passe minuit. Decoupee au calendrier, la course de
## 00 h 10 ouvrait une journee neuve : nouveau CSV, historique vide, en plein
## evenement. La journee bascule donc a 5 h locales, heure ou aucun goldsprint
## ne court. Une heure absente vaut MIDI, pas minuit : `{2026, 8, 31}` designe
## la journee du 31, et non celle qui commence a 5 h le 30.
static func operating_day(now: Dictionary) -> Dictionary:
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": now["year"], "month": now["month"], "day": now["day"],
		"hour": int(now.get("hour", 12)), "minute": int(now.get("minute", 0)),
		"second": int(now.get("second", 0)),
	})
	return Time.get_datetime_dict_from_unix_time(unix - DAY_ROLLOVER_HOUR * 3600)


static func daily_log_name(now: Dictionary = Time.get_datetime_dict_from_system()) -> String:
	var day := operating_day(now)
	return "%04d_%02d_%02d_QermesseRaceLog.csv" % [day["year"], day["month"], day["day"]]


## Cree le dossier s'il manque. Rend false et remplit `problem` en cas d'echec —
## un disque plein la veille d'un evenement doit se voir, pas se deviner.
static func ensure_dir(path: String, problem: Array[String] = []) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	var code := DirAccess.make_dir_recursive_absolute(path)
	if code != OK:
		problem.append("impossible de creer %s (erreur %d)" % [path, code])
		return false
	return true
