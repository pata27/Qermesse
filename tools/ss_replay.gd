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

	var replayed := Replay.replay(loaded)
	if replayed == null:
		print("%-28s  SANS RESULTAT  la trace ne mene a aucune fin de course" % path.get_file())
		return false

	# Le classement enregistre est la reference ; le reste est indicatif, parce
	# qu'une trace tronquee peut legitimement s'arreter plus tot.
	var same_ranking := replayed.ranking == Array(loaded.recorded_ranking)
	var verdict := "CONFORME" if same_ranking else "DIVERGENT"
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
	return same_ranking
