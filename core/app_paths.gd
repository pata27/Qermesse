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
##
## Le logiciel s'est appele SilverSprint v3 jusqu'a la 0.9.1-beta : au premier
## lancement sous son nom, `migrate_legacy` reprend les fichiers de l'ancien
## dossier s'il existe et que le nouveau n'existe pas encore.
class_name AppPaths
extends RefCounted

const APP_NAME_UNIX := "qermesse"
const APP_NAME_OTHER := "Qermesse"
const LEGACY_APP_NAME_UNIX := "silversprint"
const LEGACY_APP_NAME_OTHER := "SilverSprint"
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


static func legacy_folder() -> String:
	return LEGACY_APP_NAME_UNIX if OS.get_name() == "Linux" else LEGACY_APP_NAME_OTHER


## Reprend les fichiers de l'ancien nom (SilverSprint) sous le nouveau, une
## fois : seulement si le nouveau dossier n'existe pas encore. Rend les
## chemins copies, pour le dire a l'operateur.
static func migrate_legacy() -> Array[String]:
	var moved: Array[String] = []
	moved.append_array(
		migrate_tree(OS.get_config_dir().path_join(legacy_folder()), config_dir())
	)
	moved.append_array(migrate_tree(OS.get_data_dir().path_join(legacy_folder()), data_dir()))
	return moved


## Copie l'arbre `from` dans `to` si `from` existe et `to` pas encore. L'ancien
## dossier est laisse en place : rien n'est detruit par une migration.
static func migrate_tree(from: String, to: String) -> Array[String]:
	var moved: Array[String] = []
	if not DirAccess.dir_exists_absolute(from) or DirAccess.dir_exists_absolute(to):
		return moved
	if DirAccess.make_dir_recursive_absolute(to) != OK:
		return moved
	for name: String in DirAccess.get_files_at(from):
		if DirAccess.copy_absolute(from.path_join(name), to.path_join(name)) == OK:
			moved.append(to.path_join(name))
	for name: String in DirAccess.get_directories_at(from):
		moved.append_array(migrate_tree(from.path_join(name), to.path_join(name)))
	return moved


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
