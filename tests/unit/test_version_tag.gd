## `scripts/check_version_tag.py` — la release refuse un tag qui contredit
## `project.godot`. Eprouve ici sur le vrai script, avec le bon tag et un faux,
## comme `test_outil_rejeu` eprouve l'outil de rejeu.
extends GutTest

const SCRIPT := "scripts/check_version_tag.py"


func _run(tag: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute(
		"python3", [ProjectSettings.globalize_path("res://" + SCRIPT), "--tag", tag], output, true
	)
	return {"code": code, "text": "".join(PackedStringArray(output))}


func test_le_tag_qui_porte_la_version_du_projet_passe() -> void:
	var run := _run("v" + AppVersion.current())
	assert_eq(int(run["code"]), 0, str(run["text"]))
	assert_string_contains(str(run["text"]), AppVersion.current())


func test_un_tag_qui_contredit_le_projet_fait_echouer_la_release() -> void:
	var run := _run("v0.0.1")
	assert_eq(int(run["code"]), 1, "code 1 : la release s'arrete")
	assert_string_contains(str(run["text"]), "0.0.1", "le tag est nomme")
	assert_string_contains(str(run["text"]), AppVersion.current(), "et la version du projet aussi")
