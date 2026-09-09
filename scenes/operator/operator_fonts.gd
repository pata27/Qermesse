## Polices du panneau operateur — une seule, a chasse fixe, pour tout ce qui
## aligne des colonnes par des espaces.
##
## Les lignes de pistes, le tableau des resultats et la liste des ports sont
## rembourres (`%-18s`, `%7.1f`) pour former des colonnes. Dans la police par
## defaut, proportionnelle, ce rembourrage n'aligne rien : « Bob » et un nom
## de dix-huit caracteres ne font pas la meme largeur, et les chiffres partent
## dans tous les sens. Une police systeme a chasse fixe, presente sur les trois
## OS et mesurable en headless, rend les colonnes reelles.
class_name OperatorFonts
extends RefCounted


static func monospace() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["DejaVu Sans Mono", "Liberation Mono", "Consolas", "Menlo", "Courier New", "monospace"]
	)
	return font
