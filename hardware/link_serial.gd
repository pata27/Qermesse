## Adaptateur du module natif `SerialLink` vers l'interface de `link.gd`.
##
## Aussi mince que possible : toute la logique est en C++, couverte par les
## tests natifs de addons/serial_link/tests. Ce fichier ne fait que relayer.
extends Node

signal frame_received(kind: int, payload: Dictionary)
signal state_changed(state: int)

var _link: Node = null


func _ready() -> void:
	if _link != null:
		return
	_link = ClassDB.instantiate("SerialLink")
	add_child(_link)
	_link.frame_received.connect(func(kind: int, payload: Dictionary) -> void:
		frame_received.emit(kind, payload))
	_link.state_changed.connect(func(state: int) -> void: state_changed.emit(state))


func list_ports() -> Array:
	return _link.list_ports() if _link != null else []


func set_preferred_port(port: String) -> void:
	if _link != null:
		_link.set_preferred_port(port)


func start() -> void:
	if _link != null:
		_link.start_autoconnect()


func stop() -> void:
	if _link != null:
		_link.stop()


func send_command(cmd: String) -> bool:
	return _link.send_command(cmd) if _link != null else false


func get_firmware_version() -> String:
	return _link.get_firmware_version() if _link != null else ""


func get_link_state() -> int:
	return _link.get_link_state() if _link != null else Protocol.State.DISCONNECTED


func can_start_race() -> bool:
	return _link.can_start_race() if _link != null else false


func set_race_active(active: bool) -> void:
	if _link != null:
		_link.set_race_active(active)


func get_stats() -> Dictionary:
	return _link.get_stats() if _link != null else {}
