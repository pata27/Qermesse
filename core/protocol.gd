## Contrat serie cote GDScript — miroir de `addons/serial_link/src/line_parser.h`.
##
## Vit dans `core/` et non dans `hardware/` pour deux raisons :
##
##   * `core/` ne doit dependre de rien (docs/03 §2). Si les constantes de
##     protocole vivaient dans `hardware/`, le moteur de course en dependrait et
##     la regle serait violee des la premiere ligne du lot 2.
##   * elles doublent volontairement les enums du GDExtension, pour que le
##     simulateur et les tests headless restent utilisables sans build C++.
##
## Toute divergence avec `line_parser.h` est un bug de ce fichier : le C++ est
## la reference, lui-meme adosse a `docs/01`.
class_name Protocol
extends RefCounted

## Miroir de sslink::FrameKind (addons/serial_link/src/line_parser.h).
enum Frame {
	PROGRESS = 0,
	COUNTDOWN,
	FALSE_START,
	RIDER_FINISH,
	LENGTH_ACK,
	MOCK_ACK,
	VERSION,
	ERROR,
	KIOSK_START,
	KIOSK_STOP,
	UNKNOWN,
}

## Miroir de sslink::LinkState.
enum State {
	DISCONNECTED = 0,
	PORT_OPEN,
	IDENTIFIED,
	LINK_LOST,
}

const FIRMWARE_VERSION := "SS_v0.1.7"

## docs/01 §7 — seule calibration du systeme.
const DEFAULT_ROLLER_MM := 114.3

## docs/01 §5.5 — constante emise en mode temps et en poursuite, quelle que soit
## la duree demandee. Toute autre valeur risque de faire terminer le firmware.
const TIME_COMMAND := "t60"

const MAX_RIDERS := 4


static func state_name(state: int) -> String:
	match state:
		State.DISCONNECTED:
			return "DISCONNECTED"
		State.PORT_OPEN:
			return "PORT_OPEN"
		State.IDENTIFIED:
			return "IDENTIFIED"
		State.LINK_LOST:
			return "LINK_LOST"
	return "DISCONNECTED"


static func frame_name(kind: int) -> String:
	const NAMES := [
		"Progress", "Countdown", "FalseStart", "RiderFinish", "LengthAck",
		"MockAck", "Version", "Error", "KioskStart", "KioskStop", "Unknown",
	]
	if kind < 0 or kind >= NAMES.size():
		return "Unknown"
	return NAMES[kind]


static func circumference_mm(roller_mm: float = DEFAULT_ROLLER_MM) -> float:
	return roller_mm * PI


## docs/01 §7 — 100 m avec un rouleau de 114.3 mm donne 278 ticks.
static func ticks_for_metres(metres: float, roller_mm: float = DEFAULT_ROLLER_MM) -> int:
	if metres <= 0.0 or roller_mm <= 0.0:
		return 0
	return int(floor(metres * 1000.0 / circumference_mm(roller_mm)))


## docs/01 §2 — deux bornes independantes : 7 chiffres (charBuff[8]) et la plage
## d'un int 16 bits (atoi).
static func is_valid_firmware_argument(value: int) -> bool:
	return value >= 1 and value <= 32767 and str(value).length() <= 7
