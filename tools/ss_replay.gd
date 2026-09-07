## ss_replay — rejoue une course enregistree et verifie qu'elle redonne le
## meme classement.
##
##   godot --headless --script tools/ss_replay.gd -- <course.json>
##   godot --headless --script tools/ss_replay.gd -- --dossier <races/>
##   godot --headless --script tools/ss_replay.gd -- --dossier <races/> --detail
##
## `DEPANNAGE.md` demande a l'operateur d'envoyer le JSON d'une course au
## developpeur « en cas de resultat suspect : la course peut etre rejouee a
## l'identique ». C'est cet outil qui tient la promesse — sans lui, `Replay`
## n'etait appele que par les tests.
##
## Le rejeu ne relit PAS le classement enregistre : il repousse les trames
## brutes dans un moteur neuf et recalcule tout, puis compare (docs/06 §2). Une
## divergence est donc un bug du moteur, ou une trace corrompue.
##
## Sur un dossier, chaque course reelle devient un cas de test permanent : c'est
## l'argument de `core/replay.gd`, et c'est ce que cet outil rend praticable.
##
## Une trace peut etre CONFORME, DIVERGENTE, ILLISIBLE (format inconnu),
## INEXPLOITABLE (configuration invalide) ou SANS RESULTAT (la trace ne mene a
## aucune fin de course). Le fichier arrive parce que quelque chose cloche : le
## diagnostic doit viser la cause, pas ses consequences.
##
## Codes de sortie : 0 tout conforme, 1 au moins une divergence, 2 rien a lire.
extends SceneTree

var _paths: PackedStringArray = []
var _detail := false


func _initialize() -> void:
	_parse_args()
	if _paths.is_empty():
		printerr("usage : ss_replay.gd -- <course.json> | --dossier <dossier>")
		quit(2)
		return

	var diverging := 0
	for path: String in _paths:
		if not _check(path):
			diverging += 1

	print("")
	print("%d course(s) rejouee(s), %d divergence(s)" % [_paths.size(), diverging])
	quit(1 if diverging > 0 else 0)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--dossier":
				i += 1
				if i < args.size():
					_add_directory(args[i])
			"--detail":
				_detail = true
			_:
				# Ce qui commence par `--` est une option, pas un fichier : la
				# prendre pour un chemin produisait un « fichier introuvable »
				# qui accusait le disque plutot que la faute de frappe.
				if args[i].begins_with("--"):
					printerr("ECHEC : option inconnue « %s »" % args[i])
					quit(2)
					return
				_paths.append(args[i])
		i += 1


func _add_directory(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		printerr("dossier introuvable : %s" % dir)
		return
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for name: String in names:
		if name.get_extension() == "json":
			_paths.append(dir.path_join(name))


## Rejoue une course et rend `true` si elle est conforme.
func _check(path: String) -> bool:
	var loaded := Replay.load_file(path)
	if not loaded.ok:
		print("%-28s  ILLISIBLE  %s" % [path.get_file(), loaded.error])
		return false

	# UNE TRACE INEXPLOITABLE DIT POURQUOI. Une configuration invalide — un
	# couloir hors bornes dans un fichier edite a la main, une distance
	# aberrante — faisait echouer l'armement, et l'outil concluait « aucune fin
	# de course » : vrai, mais a cote de la cause. Le fichier arrive justement
	# parce que quelque chose cloche ; le diagnostic doit viser juste.
	var problems := loaded.config.validate()
	if loaded.recorded_mode_name != loaded.config.mode_name():
		problems.append(
			"mode inconnu « %s » — rejoue comme %s"
			% [loaded.recorded_mode_name, loaded.config.mode_name()]
		)
	if not problems.is_empty():
		print("%-28s  INEXPLOITABLE  %s" % [path.get_file(), ", ".join(problems)])
		return false

	var replayed := Replay.replay(loaded)
	if replayed == null:
		print("%-28s  SANS RESULTAT  la trace ne mene a aucune fin de course" % path.get_file())
		return false

	# LE CLASSEMENT NE SUFFIT PAS. Le rejeu recalcule les distances, les temps,
	# les moyennes et les pointes — il les imprimait avec `--detail` et ne les
	# comparait a rien. Une regression qui fausserait toutes les distances sans
	# changer l'ORDRE d'arrivee passait donc inapercue, sur l'outil meme que
	# `docs/06` appelle le filet de securite le plus rentable du projet.
	#
	# Les chiffres ne sont compares que si l'ordre concorde : sinon la
	# divergence de classement est la vraie nouvelle, et lister quatre ecarts
	# par-dessus ne ferait que la noyer.
	var same_ranking := replayed.ranking == Array(loaded.recorded_ranking)
	var gaps: Array[String] = []
	if same_ranking:
		gaps = Replay.figure_gaps(loaded, replayed)
	var verdict := "CONFORME" if same_ranking and gaps.is_empty() else "DIVERGENT"
	print(
		"%-28s  %-9s  %s  %d trames  %.2f s  classement %s"
		% [
			path.get_file(),
			verdict,
			loaded.config.mode_name(),
			loaded.samples.size(),
			float(replayed.elapsed_ms) / 1000.0,
			str(replayed.ranking),
		]
	)
	if not same_ranking:
		print("      enregistre : %s" % str(Array(loaded.recorded_ranking)))
	for gap: String in gaps:
		print("      %s" % gap)
	# JAMAIS VERT PAR ABSENCE. Une trace trop ancienne pour porter l'instant
	# d'elimination ne peut pas voir ses chiffres compares — mais le taire
	# laisserait croire a une verification qui n'a pas eu lieu.
	if same_ranking and not loaded.recorded_complete:
		print("      chiffres non compares : trace anterieure a `eliminated_ms`")
	if loaded.recorded_interrupted:
		# Meme distinction qu'a l'ecran : un plafond de securite est une fin
		# legitime, seul un ARRET merite le mot (docs/02 §3).
		var stopped := loaded.recorded_end_reason == int(RaceRule.EndReason.NONE)
		print(
			"      %s : %s"
			% [
				"arretee" if stopped else "decidee au plafond",
				loaded.recorded_interruption_note,
			]
		)
	if _detail:
		for rider: int in replayed.ranking:
			print(
				"      piste %d  %7.1f m  %6.2f s  moy %5.1f  max %5.1f"
				% [
					rider + 1,
					replayed.distance_m[rider],
					float(replayed.raced_ms(rider)) / 1000.0,
					replayed.avg_kph[rider],
					replayed.max_kph[rider],
				]
			)
	return same_ranking and gaps.is_empty()
