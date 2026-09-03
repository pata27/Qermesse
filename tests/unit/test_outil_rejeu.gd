## `tools/ss_replay` — l'outil qui tient la promesse de `DEPANNAGE`.
##
## « En cas de resultat suspect, envoyez le JSON de la course : elle peut etre
## rejouee a l'identique. » C'est cet outil qui la tient, et rien ne le gardait :
## `test_traces_de_reference.gd` eprouve `core/replay.gd`, pas la ligne de
## commande. L'outil pouvait cesser de fonctionner — verdict muet, code de
## sortie faux — sans que rien ne s'en aperçoive, jusqu'au soir ou un opérateur
## envoie une course et où il n'y a plus de chemin pour la relire.
##
## Il est lance en SOUS-PROCESSUS, comme un developpeur le lancerait : c'est le
## seul moyen de verifier ce que valent vraiment ses verdicts et son code de
## sortie. Un seul lancement porte les deux sens — une trace saine et une trace
## truquee — pour ne payer qu'un demarrage de Godot.
extends GutTest

const FIXTURE := "res://tests/fixtures/course-distance-4-coureurs.json"
const WORK := "user://test_rejeu"
## Dossier SEPARE, et volontairement vide. Le partager avec `WORK` faisait lire
## la trace truquee que l'autre test venait d'y ecrire : le dossier « sans rien
## a lire » contenait une divergence, et le code 2 devenait un code 1.
const EMPTY := "user://test_rejeu_vide"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EMPTY))


func after_all() -> void:
	for root: String in [WORK, EMPTY]:
		var dir := ProjectSettings.globalize_path(root)
		var handle := DirAccess.open(dir)
		if handle != null:
			for name: String in handle.get_files():
				DirAccess.remove_absolute(dir.path_join(name))
			DirAccess.remove_absolute(dir)


## Copie la trace de reference en changeant SON CLASSEMENT ENREGISTRE. Le rejeu
## recalcule tout depuis les trames brutes : il doit donc contredire ce
## classement-la, et le dire.
func _write_tampered() -> String:
	var source := FileAccess.open(ProjectSettings.globalize_path(FIXTURE), FileAccess.READ)
	assert_not_null(source, "la trace de reference est lisible")
	var data: Dictionary = JSON.parse_string(source.get_as_text())
	(data["result"] as Dictionary)["ranking"] = [0, 1, 2, 3]
	var path := ProjectSettings.globalize_path(WORK).path_join("truquee.json")
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(data))
	out.close()
	return path


func test_l_outil_de_rejeu_dit_conforme_et_divergent_au_bon_moment() -> void:
	var godot := OS.get_executable_path()
	if godot.is_empty() or not FileAccess.file_exists(godot):
		pending("binaire Godot introuvable — verifie la ou il l'est")
		return

	var output: Array = []
	var code := OS.execute(
		godot,
		[
			"--headless",
			# La consigne du projet : aucun son ne sort du PC, y compris quand
			# un test lance un second Godot.
			"--audio-driver", "Dummy",
			"--path", ProjectSettings.globalize_path("res://"),
			"--script", "tools/ss_replay.gd",
			"--",
			ProjectSettings.globalize_path(FIXTURE),
			_write_tampered(),
		],
		output,
		true
	)
	var text := str(output[0]) if not output.is_empty() else ""

	assert_string_contains(text, "CONFORME", "la trace de reference se rejoue a l'identique")
	assert_string_contains(text, "DIVERGENT", "et la trace truquee est denoncee")
	assert_string_contains(text, "1 divergence", "une seule des deux")
	# LE CODE DE SORTIE COMPTE AUTANT QUE LE TEXTE : c'est lui qu'un script de
	# CI regarde, et un outil qui imprime « DIVERGENT » en sortant a zero serait
	# pire qu'un outil absent.
	assert_eq(code, 1, "au moins une divergence : code 1")


func test_l_outil_de_rejeu_refuse_de_sortir_a_zero_sans_rien_a_lire() -> void:
	var godot := OS.get_executable_path()
	if godot.is_empty() or not FileAccess.file_exists(godot):
		pending("binaire Godot introuvable — verifie la ou il l'est")
		return
	var output: Array = []
	var code := OS.execute(
		godot,
		[
			"--headless", "--audio-driver", "Dummy",
			"--path", ProjectSettings.globalize_path("res://"),
			"--script", "tools/ss_replay.gd",
			"--", "--dossier", ProjectSettings.globalize_path(EMPTY),
		],
		output,
		true
	)
	assert_eq(code, 2, "rien a lire : code 2, distinct d'une divergence")
