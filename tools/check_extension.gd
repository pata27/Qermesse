## Verifie que le GDExtension `serial_link` est effectivement CHARGE par Godot.
##
## Compiler la bibliotheque ne suffit pas : un fichier present mais rejete par
## le moteur — mauvaise ABI, entry_symbol introuvable, chemin errone dans le
## .gdextension — donnerait une CI verte et un logiciel muet le jour J.
extends SceneTree


func _initialize() -> void:
	if not ClassDB.class_exists("SerialLink"):
		printerr("ECHEC : la classe SerialLink n'est pas enregistree.")
		printerr("  La bibliotheque est-elle presente dans addons/serial_link/bin/ ?")
		printerr("  Le entry_symbol du .gdextension correspond-il ?")
		quit(1)
		return

	var link: Node = ClassDB.instantiate("SerialLink")
	if link == null:
		printerr("ECHEC : SerialLink est enregistree mais ne s'instancie pas.")
		quit(1)
		return

	# Un appel reel, pas une simple introspection : on veut la preuve que le
	# code natif s'execute et rend une valeur exploitable.
	var ports: Array = link.list_ports()
	var state: int = link.get_link_state()
	var can_start: bool = link.can_start_race()

	print("module natif SerialLink : CHARGE")
	print("  ports enumeres : %d" % ports.size())
	print("  etat initial   : %s" % Protocol.state_name(state))
	print("  START autorise : %s" % ("oui" if can_start else "non (attendu au demarrage)"))

	if state != Protocol.State.DISCONNECTED:
		printerr("ECHEC : l'etat initial devrait etre DISCONNECTED.")
		quit(1)
		return
	if can_start:
		printerr("ECHEC : START ne doit JAMAIS etre autorise sans handshake (docs/01 §4).")
		quit(1)
		return

	link.free()
	quit(0)
