## Facade du lien materiel — docs/03 §2 et §3.
##
## Une seule interface, deux implementations interchangeables : le module natif
## `SerialLink` et le simulateur `link_sim.gd`. Le reste du logiciel ne sait
## jamais lequel des deux est branche, et c'est ce qui permet de developper, de
## tester en CI et de faire une demonstration sans materiel.
##
## Le rendu LIT cette facade, il ne l'ecrit jamais.
class_name Link
extends Node

## Toutes les trames recues, y compris Unknown et Error : rien n'est avale en
## silence, c'est la seule facon de diagnostiquer un boitier inconnu.
signal frame_received(kind: int, payload: Dictionary)
signal state_changed(state: int)

enum Backend { SIMULATOR, SERIAL }

var _backend: Backend = Backend.SIMULATOR
var _impl: Node = null


func _ready() -> void:
	if _impl == null:
		use_simulator()


## Bascule sur le simulateur GDScript. Toujours disponible, sur les trois OS.
func use_simulator() -> void:
	_swap(Backend.SIMULATOR, (load("res://hardware/link_sim.gd") as GDScript).new())


## Bascule sur le materiel. Rend false si le module natif n'est pas compile —
## c'est le cas d'une copie de travail fraiche, et il faut le dire clairement
## plutot que de laisser croire a une panne de cable.
func use_serial() -> bool:
	if not ClassDB.class_exists("SerialLink"):
		push_warning(
			"Le module natif SerialLink n'est pas charge. "
			+ "Compiler avec : cd addons/serial_link && scons target=template_debug"
		)
		return false
	_swap(Backend.SERIAL, (load("res://hardware/link_serial.gd") as GDScript).new())
	return true


func backend() -> Backend:
	return _backend


func is_simulated() -> bool:
	return _backend == Backend.SIMULATOR


func _swap(backend_kind: Backend, impl: Node) -> void:
	# Rien a faire si le lien demande est deja en place. Sans ce garde-fou,
	# `_ready` cree un simulateur que le controleur remplace aussitot par un
	# autre, identique : un noeud construit puis jete a chaque demarrage.
	if _impl != null and _backend == backend_kind:
		impl.free()
		return
	if _impl != null:
		_impl.stop()
		remove_child(_impl)
		_impl.queue_free()
	_backend = backend_kind
	_impl = impl
	add_child(_impl)
	_impl.frame_received.connect(_on_frame)
	_impl.state_changed.connect(_on_state)


func _on_frame(kind: int, payload: Dictionary) -> void:
	frame_received.emit(kind, payload)


func _on_state(state: int) -> void:
	state_changed.emit(state)


# --- Interface commune -------------------------------------------------------

func list_ports() -> Array:
	return _impl.list_ports()


func set_preferred_port(port: String) -> void:
	_impl.set_preferred_port(port)


func start() -> void:
	_impl.start()


func stop() -> void:
	_impl.stop()


## docs/01 §2 : la commande est validee AVANT emission, cote implementation.
func send_command(cmd: String) -> bool:
	return _impl.send_command(cmd)


func get_firmware_version() -> String:
	return _impl.get_firmware_version()


func get_link_state() -> int:
	return _impl.get_link_state()


## docs/01 §4 : seul IDENTIFIED autorise le depart d'une course.
func can_start_race() -> bool:
	return _impl.can_start_race()


## docs/01 §6.2 : arme le watchdog. A appeler au START, desarmer a la fin.
func set_race_active(active: bool) -> void:
	_impl.set_race_active(active)


func get_stats() -> Dictionary:
	return _impl.get_stats()


## Accelere le temps SIMULE. Sans effet sur le materiel, qui a sa propre
## horloge : la methode est volontairement silencieuse dans ce cas plutot que
## de lever, pour que l'appelant n'ait pas a savoir quel lien est branche.
func set_simulation_speed(scale: float) -> void:
	if _impl.has_method("set_simulation_speed"):
		_impl.set_simulation_speed(scale)


## Nombre de capteurs du boîtier SIMULÉ. Sans effet sur le matériel, dont le
## câblage ne se change pas par logiciel.
func set_simulator_riders(count: int) -> void:
	if _impl.has_method("set_wired_riders"):
		_impl.set_wired_riders(count)


## Profil du boîtier SIMULÉ. Sans effet sur le matériel.
func set_simulator_profile(name: String) -> bool:
	return bool(_impl.set_profile(name)) if _impl.has_method("set_profile") else false


## Profils du boîtier SIMULÉ ; vide sur le matériel, qui n'en a pas.
func simulator_profiles() -> Array:
	return _impl.profiles() if _impl.has_method("profiles") else []


## Coupure et retour du lien SIMULÉ — docs/01 §6.2, pour éprouver le délai de
## grâce du PC sans arracher de câble. Sans effet sur le matériel.
func inject_link_loss() -> void:
	if _impl.has_method("inject_link_loss"):
		_impl.inject_link_loss()


func inject_link_return() -> void:
	if _impl.has_method("inject_link_return"):
		_impl.inject_link_return()


## Le rider pedale pendant le decompte. Cette injection existait dans
## `link_sim` mais ne traversait pas cette facade : le faux depart etait donc
## injouable depuis l'application, et `FALSE_START` restait le seul evenement
## du CSV qu'aucun test n'atteignait.
func inject_false_start(rider: int) -> void:
	if _impl.has_method("inject_false_start"):
		_impl.inject_false_start(rider)


func inject_phantom_tick(rider: int) -> void:
	if _impl.has_method("inject_phantom_tick"):
		_impl.inject_phantom_tick(rider)


## Un accuse de longueur different de celui demande — docs/01 §2.
func inject_length_ack(ticks: int) -> void:
	if _impl.has_method("inject_length_ack"):
		_impl.inject_length_ack(ticks)


## Une trame illisible sur la ligne — docs/07 §6. Elle doit remonter en
## `UNKNOWN` et se dire a l'operateur, jamais etre avalee en silence.
func inject_corrupt_frame() -> void:
	if _impl.has_method("inject_corrupt_frame"):
		_impl.inject_corrupt_frame()


func inject_dropped_frames(count: int) -> void:
	if _impl.has_method("inject_dropped_frames"):
		_impl.inject_dropped_frames(count)
