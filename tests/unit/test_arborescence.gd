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


## Constantes declarees et jamais lues — regle 5 de `docs/06` §1, dans l'esprit.
##
## « Un fichier non reference est supprime, pas laisse au cas ou. » Une CONSTANTE
## que rien ne lit est le meme genre de promesse non tenue, en plus discret : le
## `TARGET_FPS := 60.0` du moniteur annoncait le budget de `docs/04` et ne
## servait a rien, le `EVENTS` de l'enregistreur listait les huit evenements du
## CSV sans que rien ne s'y refere, et le `REFRESH_S` de `ss_monitor` promettait
## un rafraichissement a 10 Hz que personne n'appliquait.
##
## Chaque constante doit etre lue quelque part — dans son fichier ou ailleurs.
func test_aucune_constante_n_est_declaree_pour_rien() -> void:
	var texts: Dictionary = {}
	for root: String in SCANNED:
		var files := PackedStringArray()
		_walk(root, files)
		for path: String in files:
			if path.get_extension() != "gd":
				continue
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				texts[path] = file.get_as_text()

	# LES COMMENTAIRES NE COMPTENT PAS. Nommer une constante dans une phrase ne
	# la rend pas lue — et ce test s'etait lui-meme desarme en citant deux noms
	# dans sa propre documentation.
	var corpus := ""
	for text: Variant in texts.values():
		corpus += _without_comments(str(text))

	var dead: Array[String] = []
	var declaration := RegEx.create_from_string("(?m)^const ([A-Z][A-Z0-9_]*)")
	for path: Variant in texts.keys():
		for found: RegExMatch in declaration.search_all(str(texts[path])):
			var name := found.get_string(1)
			var uses := RegEx.create_from_string("\\b%s\\b" % name).search_all(corpus).size()
			if uses <= 1:
				dead.append("%s : %s" % [str(path).get_file(), name])
	assert_eq(dead, [] as Array[String], "des constantes que rien ne lit")


## Retire les commentaires d'une source. Une ligne qui commence par `#` saute
## entierement ; un `#` en fin de ligne coupe le reste, sauf s'il est dans une
## chaine — les couleurs `"#0B0E14"` en sont pleines, d'ou le compte de
## guillemets.
static func _without_comments(source: String) -> String:
	var out := ""
	for line: String in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var quotes := 0
		var kept := ""
		for index: int in range(line.length()):
			var glyph := line[index]
			if glyph == "\"":
				quotes += 1
			elif glyph == "#" and quotes % 2 == 0:
				break
			kept += glyph
		out += kept + "\n"
	return out


## Fonctions declarees et jamais appelees — meme esprit que les constantes.
##
## Un accesseur sans appelant est une API qu'on croit avoir et qui n'a jamais
## servi. Sur les douze trouves, trois decrivaient un comportement qui meritait
## un test — la ligne par piste du panneau Course, le contrat de
## l'interpolateur, l'hysteresis du chiffre d'ecart — et neuf faisaient double
## emploi avec un accesseur voisin.
##
## Les methodes VIRTUELLES de Godot sont exclues : c'est le moteur qui les
## appelle, jamais le code. Les tests comptent comme appelants : eprouver une
## methode est un usage legitime.
func test_aucune_fonction_n_est_declaree_pour_rien() -> void:
	var texts: Dictionary = {}
	for root: String in SCANNED:
		var files := PackedStringArray()
		_walk(root, files)
		for path: String in files:
			if path.get_extension() != "gd":
				continue
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				texts[path] = _without_comments(file.get_as_text())

	var corpus := ""
	for text: Variant in texts.values():
		corpus += str(text)

	var virtual: Array[String] = [
		"_ready", "_init", "_process", "_physics_process", "_notification",
		"_enter_tree", "_exit_tree", "_input", "_initialize", "_draw",
		"before_each", "before_all", "after_each", "after_all",
	]
	var dead: Array[String] = []
	var declaration := RegEx.create_from_string("(?m)^(?:static )?func ([a-zA-Z_][a-zA-Z0-9_]*)\\(")
	for path: Variant in texts.keys():
		if str(path).contains("/tests/"):
			continue
		for found: RegExMatch in declaration.search_all(str(texts[path])):
			var name := found.get_string(1)
			if virtual.has(name) or name.begins_with("test_"):
				continue
			var uses := RegEx.create_from_string("\\b%s\\b" % name).search_all(corpus).size()
			if uses <= 1:
				dead.append("%s : %s" % [str(path).get_file(), name])
	assert_eq(dead, [] as Array[String], "des fonctions que personne n'appelle")


## Toute alerte montree a l'operateur est documentee — `docs/DEPANNAGE.md`.
##
## Ce guide est son seul recours un soir de course : il y cherche le message
## qu'il a sous les yeux. Sept des douze alertes du controleur n'y figuraient
## pas — dont « PISTE 2 : aucun tick depuis le depart », qui est precisement
## celle qu'on veut trouver quand un coureur ne demarre pas.
##
## On compare les DEBUTS de message, avant le premier `%` : c'est ce que
## l'operateur lit et ce qu'il peut chercher.
func test_chaque_alerte_de_l_operateur_est_dans_le_depannage() -> void:
	var source := FileAccess.open("res://scenes/app_controller.gd", FileAccess.READ)
	assert_not_null(source, "le controleur est lisible")
	var guide := FileAccess.open("res://docs/DEPANNAGE.md", FileAccess.READ)
	assert_not_null(guide, "le guide de depannage est lisible")
	var text := guide.get_as_text()

	var undocumented: Array[String] = []
	var pattern := RegEx.create_from_string('notice\\.emit\\(\\s*"([^"]+)"')
	for found: RegExMatch in pattern.search_all(source.get_as_text()):
		var message := found.get_string(1)
		var head := message.split("%")[0].strip_edges()
		# Un message purement variable — « lien : %s » — n'a pas de debut a
		# chercher ; c'est l'etat du lien qui est documente, pas le prefixe.
		if head.length() < 8:
			continue
		if not text.contains(head):
			undocumented.append(head)
	assert_eq(undocumented, [] as Array[String], "des alertes absentes de DEPANNAGE.md")


## La palette de `docs/04` §2 est celle du code.
##
## `#161B26`, l'« ardoise » que le document donnait pour la piste, n'existait
## nulle part : le rendu utilise un bois clair, avec sa raison ecrite a cote —
## une piste sombre sur fond anthracite disparait. Le code avait raison, le
## document etait reste en arriere, et rien ne les confrontait.
func test_la_palette_du_document_est_celle_du_code() -> void:
	var guide := FileAccess.open("res://docs/04-DIRECTION-ARTISTIQUE.md", FileAccess.READ)
	assert_not_null(guide, "le document se lit")
	var palette := guide.get_as_text()
	var table := palette.substr(palette.find("## 2. Palette"), 1200)

	var sources := ""
	for root: String in ["res://core", "res://scenes", "res://audio", "res://art"]:
		var files := PackedStringArray()
		_walk(root, files)
		for path: String in files:
			if path.get_extension() != "gd" and path.get_extension() != "gdshader":
				continue
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				sources += file.get_as_text()

	var missing: Array[String] = []
	for found: RegExMatch in RegEx.create_from_string("#[0-9A-Fa-f]{6}").search_all(table):
		var hex := found.get_string(0)
		if not sources.contains(hex):
			missing.append(hex)
	assert_eq(missing, [] as Array[String], "des couleurs annoncees que le rendu n'emploie pas")


## L'arbre de `docs/03` §2 est celui du dépôt.
##
## C'est la premiere chose que lit quelqu'un qui arrive. Il omettait `tools/` —
## vingt-six fichiers, dont les cinq outils de preuve que la CI lance — et
## dessinait `scenes/shared/` et `tests/replay/`, qui n'existent pas dans le
## depot. Un plan faux oriente moins bien que pas de plan.
func test_l_arbre_de_l_architecture_est_celui_du_depot() -> void:
	var guide := FileAccess.open("res://docs/03-ARCHITECTURE.md", FileAccess.READ)
	assert_not_null(guide, "le document se lit")
	var text := guide.get_as_text()
	var block := text.substr(text.find("SilverSprint-v3/"))
	block = block.substr(0, block.find("```"))

	# Chaque dossier dessine doit exister ET contenir quelque chose. Un dossier
	# vide dessine dans le plan est pire qu'absent : on le cherche.
	var missing: Array[String] = []
	var folder := RegEx.create_from_string("(?m)^[^a-z]*([a-z0-9_]+)/")
	for found: RegExMatch in folder.search_all(block):
		var name := found.get_string(1)
		if name == "SilverSprint-v3" or missing.has(name):
			continue
		if not _folder_has_content(name):
			missing.append(name)
	assert_eq(missing, [] as Array[String], "des dossiers dessines vides ou absents")

	# Et chaque dossier de code du projet doit y figurer.
	var absent: Array[String] = []
	for root: String in ["core", "hardware", "scenes", "audio", "tools", "tests", "art"]:
		if not block.contains(root + "/"):
			absent.append(root)
	assert_eq(absent, [] as Array[String], "des dossiers du depot absents de l'arbre")


## Un dossier de ce nom existe-t-il quelque part, avec au moins un fichier qui
## ne soit pas un simple `.gitkeep` — le sien ou celui d'un sous-dossier ?
func _folder_has_content(name: String, root: String = "res://") -> bool:
	var dir := DirAccess.open(root)
	if dir == null:
		return false
	var found := false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty() and not found:
		if dir.current_is_dir() and not entry.begins_with("."):
			var path := root.path_join(entry)
			if entry == name:
				found = _has_any_file(path)
			else:
				found = _folder_has_content(name, path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Un fichier, n'importe ou sous ce chemin, `.gitkeep` mis a part.
func _has_any_file(path: String) -> bool:
	for file: String in DirAccess.get_files_at(path):
		if file != ".gitkeep":
			return true
	for sub: String in DirAccess.get_directories_at(path):
		if not sub.begins_with(".") and _has_any_file(path.path_join(sub)):
			return true
	return false
