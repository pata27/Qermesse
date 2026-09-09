## La version du logiciel — UNE source, `project.godot`.
##
## Elle n'apparaissait nulle part : ni dans le titre de la fenetre, ni dans le
## JSON de course que DEPANNAGE fait envoyer au developpeur, qui ne pouvait pas
## savoir quel build l'avait ecrit. Et les presets d'export en declaraient une
## autre — 0.3.0 pour un logiciel en 0.9.0-beta. `test_arborescence` tient
## desormais les presets alignes sur `project.godot`.
class_name AppVersion
extends RefCounted


static func current() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


## La partie numerique seule — ce que macOS accepte comme version courte.
static func numeric() -> String:
	var version := current()
	var dash := version.find("-")
	return version if dash < 0 else version.substr(0, dash)
