# Point d'entree des tests headless.
#
#   godot --headless --script tests/run.gd
#
# Sort en 0 si tout passe, en 1 sinon — c'est le jalon J0 de docs/05.
# La configuration vit dans .gutconfig.json a la racine du projet, pour que la
# commande reste identique en local et en CI, sans arguments a retenir.
extends SceneTree


func _init() -> void:
	var version_conversion: Object = load("res://addons/gut/version_conversion.gd")
	if version_conversion.error_if_not_all_classes_imported():
		quit(1)
		return

	# Force le chargement statique de GUT avant toute instanciation.
	var _loader: Object = load("res://addons/gut/gut_loader.gd")

	var iterations := 0
	while Engine.get_main_loop() == null and iterations < 20:
		await create_timer(0.01).timeout
		iterations += 1
	if Engine.get_main_loop() == null:
		push_error("La boucle principale n'a pas demarre.")
		quit(1)
		return

	# CHAQUE FICHIER DE TESTS DOIT SE CHARGER, verifie ICI, hors de GUT. GUT
	# ecarte en silence un fichier qui ne se parse pas et rend une suite verte,
	# amputee — 372 tests tombes a 357 sans un seul echec. Une garde GUT le
	# detectait, mais elle vivait dans un fichier de tests : le jour ou c'est
	# celui-la qui ne se parse plus, elle disparait avec lui. Un total qui
	# baisse est un echec ; le lanceur le dit avant de lancer quoi que ce soit.
	var broken := _unloadable_test_files()
	if not broken.is_empty():
		push_error("Fichier(s) de tests illisible(s), la suite ne part pas : %s" % ", ".join(broken))
		quit(1)
		return
	var cli: Node = load("res://addons/gut/cli/gut_cli.gd").new()
	get_root().add_child(cli)
	cli.main()


## Les scripts de `tests/unit` que Godot ne peut pas instancier : erreur de
## parse, identifiant inconnu, classe non importee. `load` les rend sans
## pouvoir les instancier ; GUT, lui, les ignorerait.
func _unloadable_test_files() -> Array[String]:
	var broken: Array[String] = []
	var dir := DirAccess.open("res://tests/unit")
	if dir == null:
		return ["res://tests/unit introuvable"]
	for name: String in dir.get_files():
		if not name.begins_with("test_") or name.get_extension() != "gd":
			continue
		var script: Variant = load("res://tests/unit/" + name)
		if script == null or not (script as Script).can_instantiate():
			broken.append(name)
	return broken
