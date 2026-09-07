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
		last_error = "dossier illisible : %s" % path.get_base_dir()
		return false

	# LE RENOMMAGE D'ABORD, la suppression seulement s'il refuse.
	#
	# L'ancienne version supprimait la destination AVANT de renommer. Entre les
	# deux, plus aucun fichier n'existait a ce chemin : une coupure exactement
	# la — et c'est le seul moment ou elle fait des degats — perdait roster et
	# reglages, precisement ce que l'ecriture atomique existe pour empecher. Le
	# commentaire en tete de ce fichier promettait « l'ancien fichier intact »,
	# et la promesse avait une fenetre.
	#
	# Sur les systemes POSIX, renommer par-dessus un fichier existant est ATOMIQUE
	# et remplace la destination — verifie. La suppression ne sert donc a rien, et
	# elle nuit. On la garde en repli pour les systemes dont le renommage refuse
	# une destination occupee : la fenetre y subsiste, mais elle n'est plus
	# ouverte partout.
	if dir.rename(temp.get_file(), path.get_file()) == OK:
		return true
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	if dir.rename(temp.get_file(), path.get_file()) == OK:
		return true
	last_error = "renommage impossible : %s" % path
	return false


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
