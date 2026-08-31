## Emplacements des donnees, par systeme — docs/02 §5.
##
## Godot expose `user://`, mais son emplacement par defaut
## (`~/.local/share/godot/app_userdata/...`) n'est pas celui que la spec impose
## et serait introuvable pour un operateur qui cherche son CSV. On resout donc
## les chemins explicitement.
##
##   Linux    ~/.config/silversprint/  et  ~/.local/share/silversprint/
##   macOS    ~/Library/Application Support/SilverSprint/
##   Windows  %APPDATA%\SilverSprint\
class_name AppPaths
extends RefCounted

const APP_NAME_UNIX := "silversprint"
const APP_NAME_OTHER := "SilverSprint"


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


static func daily_log_name(now: Dictionary = Time.get_datetime_dict_from_system()) -> String:
	return "%04d_%02d_%02d_SilverSprintRaceLog.csv" % [now["year"], now["month"], now["day"]]


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
