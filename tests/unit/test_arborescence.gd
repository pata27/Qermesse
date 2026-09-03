## Regle 5 de `docs/06` §1 — « Pas d'asset orphelin ».
##
## « Un fichier non reference est supprime, pas laisse au cas ou. » La regle
## etait tenue a la main, donc pas tenue : un `.uid` d'un shader fusionne dans
## un autre est reste dans le depot, sans son `.gdshader` et sans que rien ne
## le nomme. Godot ne nettoie jamais ces fichiers — il les cree a l'import et
## les laisse a la suppression.
##
## Deux verifications, l'une et l'autre en lecture seule et sans ecran.
extends GutTest

## Dossiers du PROJET. `addons/` en est exclu : c'est du code tiers, vendorise,
## qu'on ne corrige pas ici — GUT y traine d'ailleurs un `.uid` orphelin qui
## n'est pas notre affaire.
const SCANNED: Array[String] = [
	"res://art",
	"res://core",
	"res://hardware",
	"res://scenes",
	"res://tools",
	"res://tests",
]
## Extensions dans lesquelles une reference peut se trouver.
const SOURCES: Array[String] = ["gd", "tscn", "tres", "gdshader", "godot"]


func _walk(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if dir.current_is_dir():
			_walk(full, out)
		else:
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _all_files() -> PackedStringArray:
	var files := PackedStringArray()
	for root: String in SCANNED:
		_walk(root, files)
	# Le fichier de projet lui-meme, sans parcourir la racine : la remonter
	# ramenait `addons/`, que l'on vient justement d'exclure.
	files.append("res://project.godot")
	return files


func test_aucun_uid_ne_survit_a_son_fichier() -> void:
	# Un `.uid` sans sa ressource est le fantome d'un fichier supprime. Il ne
	# casse rien, et c'est bien le probleme : il reste des mois.
	var orphans := PackedStringArray()
	for path: String in _all_files():
		if path.get_extension() != "uid":
			continue
		if not FileAccess.file_exists(path.trim_suffix(".uid")):
			orphans.append(path)
	assert_eq(
		Array(orphans), [],
		"des .uid sans ressource : Godot ne les nettoie pas, il faut les supprimer"
	)


func test_aucun_asset_n_est_orphelin() -> void:
	# Chaque fichier de `art/` doit etre nomme quelque part — par son nom ou par
	# son uid, les scenes referencant souvent par uid.
	var sources := ""
	for path: String in _all_files():
		if not SOURCES.has(path.get_extension()) or path.begins_with("res://art"):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			sources += file.get_as_text()

	var orphans := PackedStringArray()
	var assets := PackedStringArray()
	_walk("res://art", assets)
	for path: String in assets:
		if path.get_extension() == "uid":
			continue
		var named := sources.contains(path.get_file())
		# Un asset peut n'etre reference que par son uid.
		var uid_file := FileAccess.open(path + ".uid", FileAccess.READ)
		if not named and uid_file != null:
			named = sources.contains(uid_file.get_as_text().strip_edges())
		if not named:
			orphans.append(path)
	assert_eq(Array(orphans), [], "assets que plus rien ne nomme — docs/06 §1, regle 5")
