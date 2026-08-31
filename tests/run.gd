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

	var cli: Node = load("res://addons/gut/cli/gut_cli.gd").new()
	get_root().add_child(cli)
	cli.main()
