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
	# Les VARIABLES PRIVEES entrent dans le meme compte. Une `var _x` que rien
	# ne relit est morte au meme titre qu'une constante — `link_sim.gd` en
	# gardait une, `_pending_faults`, jamais lue depuis sa declaration. GDScript
	# n'y donne pas acces de l'exterieur : une seule occurrence suffit a
	# conclure.
	var declaration := RegEx.create_from_string(
		"(?m)^(?:const ([A-Z][A-Z0-9_]*)|var (_[a-z][a-z0-9_]*))"
	)
	for path: Variant in texts.keys():
		for found: RegExMatch in declaration.search_all(str(texts[path])):
			var name := found.get_string(1)
			var private := name.is_empty()
			if private:
				name = found.get_string(2)
			# Une constante peut etre lue d'ailleurs ; une variable privee, non.
			var haystack: String = str(texts[path]) if private else corpus
			var uses := RegEx.create_from_string("\\b%s\\b" % name).search_all(haystack).size()
			if uses <= 1:
				dead.append("%s : %s" % [str(path).get_file(), name])
	assert_eq(dead, [] as Array[String], "des declarations que rien ne relit")


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
	# TOUT CE QUI PEUT ECRIRE DANS LE JOURNAL, pas le seul controleur.
	#
	# La garde ne lisait que `app_controller.gd`, et le journal du panneau
	# Course a deux autres sources : la vitrine, qui passe par le signal du
	# controleur, et le panneau lui-meme, qui y ecrit directement les faits de
	# course — faux depart, elimination, arrivee. Quatre messages echappaient
	# donc a la verification, et la table du guide affirme pourtant lister
	# « chacun de ceux que le logiciel peut y ecrire ».
	#
	# Une garde qui ne regarde qu'un fichier protege ce fichier, pas la
	# promesse.
	var guide := FileAccess.open("res://docs/DEPANNAGE.md", FileAccess.READ)
	assert_not_null(guide, "le guide de depannage est lisible")
	var text := guide.get_as_text()

	var corpus := ""
	for path: String in [
		"res://scenes/app_controller.gd",
		"res://scenes/attract_mode.gd",
		"res://scenes/operator/panel_race.gd",
	]:
		var source := FileAccess.open(path, FileAccess.READ)
		assert_not_null(source, "%s est lisible" % path)
		corpus += _joined_literals(source.get_as_text())

	var undocumented: Array[String] = []
	# `notice.emit` pour les alertes, `_push_notice` pour ce que le panneau
	# ecrit de lui-meme : les deux atterrissent au meme endroit sous les yeux de
	# l'operateur, donc les deux comptent.
	var pattern := RegEx.create_from_string(
		'(?:notice\\.emit|_push_notice)\\(\\s*"([^"]+)"'
	)
	for found: RegExMatch in pattern.search_all(corpus):
		# LE PLUS LONG MORCEAU FIXE, pas le debut. Chercher ce qui precede le
		# premier « % » exemptait en silence toute alerte ouvrant sur la piste
		# concernee — « PISTE %d : ... » donne « PISTE », cinq lettres, sous le
		# seuil. Les deux alertes de cette famille etaient documentees, mais par
		# chance : la garde ne les regardait pas. Un morceau fixe long est un
		# bien meilleur ancrage qu'un prefixe, et il tombe au milieu de la
		# phrase, la ou elle dit quelque chose.
		# AU MOINS UN MORCEAU FIXE dans le guide, pas le plus long.
		#
		# Une table d'entree cite ce qui IDENTIFIE un message, pas la phrase
		# entiere : « LONGUEUR : le boîtier a compris N ticks, M demandés »
		# s'arrete la ou l'operateur a compris de quoi il s'agit, et laisse la
		# suite — les consequences, la marche a suivre — a ses autres colonnes.
		# Exiger le plus long morceau revenait a exiger la phrase entiere, ce
		# qui accusait des messages parfaitement documentes.
		#
		# Ce qu'on veut verifier est plus modeste et plus juste : que le guide
		# porte de ce message quelque chose d'assez long pour qu'on le
		# reconnaisse.
		var message := found.get_string(1)
		var pieces := message.split("%")
		var identifiable := false
		var candidates := PackedStringArray()
		for index: int in range(pieces.size()):
			# Le premier caractere apres un « % » est le format — d, s, f, .1f.
			# SEULEMENT APRES UN « % » : applique au premier morceau, qui n'en
			# suit aucun, cette coupe mangeait sa premiere lettre. « Module
			# natif absent » devenait « odule natif absent », qui se trouvait
			# quand meme dans le guide — par correspondance partielle, donc par
			# chance.
			var fixed: String = pieces[index]
			if index > 0:
				fixed = RegEx.create_from_string("^[0-9.]*[a-zA-Z]").sub(fixed, "")
			fixed = fixed.strip_edges()
			if fixed.length() < 12:
				continue
			# LES TRENTE PREMIERS CARACTERES, pas le morceau entier. Une table
			# d'entree cite ce qui IDENTIFIE un message et s'arrete la ou
			# l'operateur a compris de quoi il s'agit ; la suite — consequences,
			# marche a suivre — vit dans ses autres colonnes. Exiger le morceau
			# entier revenait a exiger la phrase, ce qui accusait des messages
			# parfaitement documentes.
			var probe := fixed.substr(0, 30)
			candidates.append(probe)
			if text.contains(probe):
				identifiable = true
		# Un message purement variable — « lien : %s » — n'a aucun morceau fixe
		# a chercher ; c'est l'etat du lien qui est documente, pas le prefixe.
		if candidates.is_empty() or identifiable:
			continue
		undocumented.append(candidates[0])
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


## La sortie de la suite reste lisible.
##
## `wait_frames` est un alias deprecie de `wait_physics_frames` : chaque appel
## imprimait un avertissement, soit 829 lignes par execution. Ce bruit noie les
## messages qui comptent — il a fallu grepper autour toute une nuit — et c'est
## exactement le defaut deja corrige sur `ss_monitor` et `ss_probe`, ou une
## ligne d'etat repeinte trop souvent enterrait le diagnostic.
func test_la_suite_n_appelle_aucune_fonction_depreciee() -> void:
	var offenders: Array[String] = []
	var files := PackedStringArray()
	_walk("res://tests", files)
	for path: String in files:
		if path.get_extension() != "gd":
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := _without_comments(file.get_as_text())
		# `wait_frames` sans prefixe : `wait_physics_frames` contient la chaine.
		if RegEx.create_from_string("(?<![_a-z])wait_frames\\(").search(text) != null:
			offenders.append(path.get_file())
	assert_eq(offenders, [] as Array[String], "des appels a `wait_frames`, deprecie")


## Un texte destine a un humain nomme la piste en 1..4, jamais son indice.
##
## `abort("faux départ piste %d" % rider)` ecrivait l'indice BRUT : un faux
## depart sur la piste 2 accusait publiquement « piste 1 », au bandeau, au CSV
## et dans l'historique du jour. `tick_filter.gd` porte pourtant la regle,
## commentee, depuis toujours.
##
## La verification est etroite exprès : toute chaine qui contient « piste %d »
## doit formater `rider + 1` — ou nommer explicitement un INDICE, seul cas ou la
## valeur brute a du sens.
func test_aucun_texte_ne_nomme_une_piste_par_son_indice() -> void:
	var offenders: Array[String] = []
	for root: String in ["res://core", "res://scenes", "res://audio", "res://tools"]:
		var files := PackedStringArray()
		_walk(root, files)
		for path: String in files:
			if path.get_extension() != "gd":
				continue
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				continue
			var lines := file.get_as_text().split("\n")
			for index: int in range(lines.size()):
				var line: String = lines[index]
				if not line.to_lower().contains("piste %d"):
					continue
				if line.to_lower().contains("indice de piste"):
					continue
				# Le format et son argument tiennent parfois sur deux lignes.
				var window := line
				for ahead: int in range(1, 4):
					if index + ahead < lines.size():
						window += lines[index + ahead]
				if not window.contains("+ 1"):
					offenders.append("%s:%d" % [str(path).get_file(), index + 1])
	assert_eq(offenders, [] as Array[String], "des pistes nommees par leur indice")


## La table du MANUEL dit MOT POUR MOT ce que l'operateur lit sous les boutons.
##
## `RaceEngine.state_label` affirme dans sa docstring « voir la table du MANUEL,
## qui est la meme » — une egalite declaree que rien ne tenait. Elle avait
## d'ailleurs deja glisse : cinq des six lignes du manuel etaient ecrites sans
## accents, quand l'ecran en porte. Un operateur qui cherche dans le manuel la
## ligne qu'il a sous les yeux la cherche AU MOT PRES ; deux redactions qui
## divergent lentement, c'est un manuel qu'on cesse d'ouvrir.
func test_le_manuel_reprend_mot_pour_mot_les_lignes_d_etat() -> void:
	var file := FileAccess.open("res://docs/MANUEL-OPERATEUR.md", FileAccess.READ)
	assert_not_null(file, "le manuel est la")
	var manual := file.get_as_text()
	var missing: Array[String] = []
	for state: RaceEngine.State in [
		RaceEngine.State.IDLE,
		RaceEngine.State.ARMING,
		RaceEngine.State.COUNTDOWN,
		RaceEngine.State.RUNNING,
		RaceEngine.State.FINISHED,
		RaceEngine.State.RESULTS,
	]:
		# La ligne du tableau, bornee par ses barres : « décompte » seul se
		# trouverait dans n'importe quelle phrase du manuel.
		if not manual.contains("| %s |" % RaceEngine.state_label(state)):
			missing.append(RaceEngine.state_label(state))
	assert_eq(missing, [] as Array[String], "des lignes d'etat absentes de la table du manuel")


## Chaque message DOCUMENTE existe encore dans le code — le sens inverse.
##
## `test_chaque_alerte_de_l_operateur_est_dans_le_depannage` verifie qu'une
## alerte ajoutee au code est ecrite dans le guide. Rien ne verifiait l'autre
## sens, et c'est la meme derive vue de l'autre bout : un message reformule ou
## supprime laisse dans `DEPANNAGE` une ligne qui ne correspond plus a rien.
##
## Ce defaut-la est plus vicieux que son symetrique. Une alerte non documentee
## laisse l'operateur sans reponse — il cherche ailleurs. Un guide qui nomme un
## message que le logiciel n'emet plus l'envoie chercher un FANTOME : il attend
## quelque chose qui ne viendra jamais, et conclut que le materiel est en cause.
func test_chaque_message_du_depannage_existe_encore_dans_le_code() -> void:
	var guide := FileAccess.open("res://docs/DEPANNAGE.md", FileAccess.READ)
	assert_not_null(guide, "le guide se lit")
	var text := guide.get_as_text()
	var marker := "## Tous les messages du panneau Course"
	assert_true(text.contains(marker), "la table des messages est toujours la")

	var corpus := ""
	for path: String in [
		"res://scenes/app_controller.gd",
		"res://hardware/link.gd",
		"res://scenes/operator/panel_hardware.gd",
		"res://scenes/operator/panel_race.gd",
		"res://scenes/attract_mode.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			corpus += _joined_literals(file.get_as_text())

	var phantom: Array[String] = []
	for line: String in text.substr(text.find(marker)).split("\n"):
		if not line.begins_with("| `"):
			continue
		# Le premier `…` de la ligne est le message ; le reste de la ligne est
		# son explication, qui n'a pas a se retrouver dans le code.
		var quoted := line.split("`")
		if quoted.size() < 2:
			continue
		# LE PLUS LONG MORCEAU ENTRE DEUX MARQUES, pas ce qui precede la
		# premiere. Tronquer au premier « N » reduisait « FAUX DÉPART piste N »
		# a lui-meme, faute de marque reconnue, et « PISTE N : aucun tick… » a
		# « PISTE » — cinq lettres, sous le seuil, donc silencieusement exempte.
		# C'est le meme bailonnage que la garde symetrique a deja connu : une
		# regle de decoupe qui rend un morceau trop court exempte au lieu
		# d'accuser, et personne ne le voit.
		#
		# Le guide ecrit ses variables `N`, `R`, `X` la ou le code ecrit `%d` ou
		# `%s` : on decoupe autour, et on garde le plus long fragment fixe.
		var longest := ""
		for fragment: String in _without_placeholders(quoted[1]):
			if fragment.length() > longest.length():
				longest = fragment
		if longest.length() < 10:
			continue
		if not corpus.contains(longest):
			phantom.append(quoted[1])
	assert_eq(phantom, [] as Array[String], "des messages documentes que le code n'emet plus")


## Decoupe un message du guide autour de ses variables, et rend les morceaux
## fixes. `N`, `R` et `X` sont les marques que le guide emploie la ou le code
## ecrit `%d` ou `%s` ; `…` marque un motif libre.
static func _without_placeholders(message: String) -> PackedStringArray:
	var cleaned := RegEx.create_from_string("…|\\b[NRX]\\b").sub(message, "\n", true)
	var out := PackedStringArray()
	for piece: String in cleaned.split("\n"):
		out.append(piece.strip_edges())
	return out


## Recolle les litteraux ADJACENTS avant de chercher dedans.
##
## GDScript concatene `"a" + "b"` a l'analyse, et le code s'en sert pour tenir
## la limite de cent colonnes : le message du test capteurs vit sur deux lignes.
## Une recherche naive ne le trouvait pas et l'accusait d'avoir disparu — une
## garde qui accuse a tort finit ignoree.
static func _joined_literals(source: String) -> String:
	# Deux formes de couture, et il faut les deux.
	#
	# `"a" + "b"` d'abord — le cas simple. Mais le code ecrit aussi
	# `"a %d" % [x] + "b"` : l'expression de formatage se glisse ENTRE les deux
	# litteraux, et un recollage qui ne la franchit pas laisse deux morceaux la
	# ou l'operateur lira une phrase. La garde accusait alors un message
	# parfaitement present, pour la seule raison qu'il etait long.
	var joined := RegEx.create_from_string(
		'"\\s*%\\s*(?:\\[[^\\]]*\\]|\\([^)]*\\))\\s*\\+\\s*"'
	).sub(source, "", true)
	return RegEx.create_from_string('"\\s*\\+\\s*"').sub(joined, "", true)
