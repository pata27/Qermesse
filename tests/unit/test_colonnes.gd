## Les colonnes du panneau operateur — lignes de pistes, tableau des resultats,
## liste des ports — sont alignees par des espaces : elles n'existent que dans
## une police a chasse fixe (`OperatorFonts`). Ces tests mesurent les largeurs
## en pixels ; rien n'est juge a l'oeil.
extends "res://tests/support/base_operateur.gd"

func test_les_lignes_de_pistes_alignent_leurs_colonnes_quel_que_soit_le_nom() -> void:
	# La ligne etait rembourree a quatorze caracteres dans une police
	# proportionnelle : « Bob » donnait 283 px, un nom de dix-huit 369 px, et
	# les chiffres partaient dans tous les sens. Chasse fixe, rembourrage a la
	# largeur que l'ecran public montre : deux lignes, meme largeur.
	assert_true(await _await_identified())
	_controller.roster.rider(0).name = "Bob"
	_controller.roster.rider(1).name = "Maximilien-Alexanx"
	assert_true(_controller.engine.arm(_controller.current_config(), 0))
	_controller.engine.race_state().apply_sample([100, 100, 0, 0], 5000)
	var race_panel := _panel.race_panel()
	race_panel.refresh()
	await get_tree().process_frame
	var lanes: Array = race_panel.get("_lanes")
	var short_line: Label = lanes[0]
	var long_line: Label = lanes[1]
	assert_eq(short_line.text.length(), long_line.text.length(), "meme nombre de caracteres")
	assert_almost_eq(
		short_line.get_minimum_size().x, long_line.get_minimum_size().x, 1.0,
		"et la meme largeur : la police est a chasse fixe"
	)
	assert_string_contains(long_line.text, "Maximilien-Alexanx", "le nom entier tient")
	_controller.engine.abort("fin du test")


func test_le_tableau_des_resultats_et_la_liste_des_ports_alignent_leurs_colonnes() -> void:
	# Meme defaut que les lignes de pistes, sur deux autres surfaces : le
	# tableau Resultats (387 px pour « Bob », 442 pour un nom de dix-huit) et
	# la liste des ports. Chasse fixe partagee : deux lignes de meme longueur
	# font la meme largeur.
	assert_true(await _await_identified())
	_controller.roster.rider(0).name = "Bob"
	_controller.roster.rider(1).name = "Maximilien-Alexanx"
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	for i: int in range(1200):
		await wait_physics_frames(1)
		if _controller.history().size() > 0:
			break
	var table: RichTextLabel = _panel.results_panel().get("_table")
	var font: Font = table.get_theme_font("normal_font")
	var size: int = table.get_theme_font_size("normal_font_size")
	var rows: Array[String] = []
	for line: String in table.text.split("\n"):
		if line.contains("Bob") or line.contains("Maximilien"):
			rows.append(line)
	assert_eq(rows.size(), 2, "les deux coureurs sont au tableau")
	assert_eq(rows[0].length(), rows[1].length(), "meme nombre de caracteres")
	var w0 := font.get_string_size(rows[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w1 := font.get_string_size(rows[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	assert_almost_eq(w0, w1, 1.0, "et la meme largeur")

	var ports: ItemList = _panel.hardware_panel().get("_port_list")
	var port_font: Font = ports.get_theme_font("font")
	var narrow := port_font.get_string_size("iiiiiiii", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var wide := port_font.get_string_size("MMMMMMMM", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	assert_almost_eq(narrow, wide, 1.0, "la liste des ports est en chasse fixe")


func test_un_avertissement_long_se_plie_au_lieu_d_elargir_sa_colonne() -> void:
	# L'avertissement du roster n'avait pas de retour a la ligne : 571 px pour
	# deux pistes nommees, et la colonne prenait cette largeur — plus qu'une
	# moitie de fenetre a sa taille minimale. Mesure. Un texte se plie.
	for lane: int in range(4):
		_controller.roster.set_active(lane, true)
		_controller.roster.rider(lane).color = _controller.roster.rider(0).color
	_panel.roster_panel().refresh()
	await get_tree().process_frame
	var warning: Label = _panel.roster_panel().get("_warning")
	assert_false(warning.text.is_empty(), "quatre pistes de la meme couleur : il y a un avertissement")
	assert_lte(warning.get_minimum_size().x, 480.0, "et il ne pousse pas les murs de sa colonne")
	var firmware: Label = _panel.hardware_panel().get("_firmware_label")
	assert_false(firmware.text.is_empty())
	assert_lte(firmware.get_minimum_size().x, 480.0, "la ligne firmware non plus")
