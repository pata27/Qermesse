## Lecture et ecriture de JSON sur disque, avec ecriture atomique.
##
## L'ecriture passe par un fichier temporaire renomme ensuite. Une coupure de
## courant pendant l'ecriture laisse alors l'ancien fichier intact, au lieu d'un
## JSON tronque qui ferait perdre roster et reglages la veille d'un evenement.
class_name JsonStore
extends RefCounted

## Motif du dernier echec. `core/` ne decide PAS de la politique de
## journalisation : il rapporte, la couche applicative affiche. Un
## `push_warning` ici imposerait un canal de sortie a du code qui doit rester
## utilisable en headless, en test et en rejeu.
static var last_error: String = ""


static func write(path: String, data: Dictionary) -> bool:
	last_error = ""
	var problems: Array[String] = []
	if not AppPaths.ensure_dir(path.get_base_dir(), problems):
		last_error = ", ".join(problems)
		return false

	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "écriture impossible dans %s" % temp
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()

	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(temp.get_file(), path.get_file()) == OK


## Rend un dictionnaire vide si le fichier est absent ou illisible. Un reglage
## corrompu ne doit jamais empecher le logiciel de demarrer : on repart des
## valeurs par defaut, bruyamment.
static func read(path: String) -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "fichier absent : %s" % path
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "lecture impossible : %s" % path
		return {}
	var text := file.get_as_text()
	file.close()
	# JSON.parse_string() ecrit dans le journal du moteur avant de rendre null :
	# un fichier corrompu produirait une erreur qu'on ne veut PAS ici, puisque
	# ce cas est prevu et gere. JSON.new().parse() rend un code sans bruit.
	var json := JSON.new()
	if json.parse(text) != OK:
		last_error = (
			"JSON invalide ligne %d (%s), valeurs par défaut utilisées : %s"
			% [json.get_error_line(), json.get_error_message(), path]
		)
		return {}
	if not (json.data is Dictionary):
		last_error = "JSON invalide, un objet était attendu : %s" % path
		return {}
	return json.data
