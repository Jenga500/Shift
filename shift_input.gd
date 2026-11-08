## Input action names used by the Shift vehicle scripts, and their default
## bindings.
##
## Every script reads input through these constants, so the action names are
## defined only here. When the plugin is enabled it adds any missing action to
## the project's Input Map with the defaults below (existing actions and your own
## bindings are never touched). [method ensure_actions] does the same at runtime,
## so a car also works in a project where the plugin was never enabled.
class_name ShiftInput
extends RefCounted

## Throttle pedal, 0..1.
const GAS := &"Gas"
## Brake pedal, 0..1.
const BRAKE := &"Brake"
## Steering, each 0..1.
const STEER_LEFT := &"SteerLeft"
const STEER_RIGHT := &"SteerRight"
## Clutch pedal, 0..1, where 1 is fully pressed.
const CLUTCH := &"Clutch"
## Gear up and down (R/N/D in automatic mode).
const SHIFT_UP := &"ShiftUp"
const SHIFT_DOWN := &"ShiftDown"
## Toggles the engine on and off.
const IGNITION := &"Ignition"
## Handbrake lever, 0..1.
const HANDBRAKE := &"Handbrake"
const TOGGLE_TC := &"ToggleTC"

## Dead zone given to the actions that are created.
const DEADZONE := 0.2

## Default bindings: action -> [physical key, joypad button index or -1,
## joypad axis or -1, axis direction].
const DEFAULTS := {
	GAS: [KEY_W, -1, JOY_AXIS_TRIGGER_RIGHT, 1.0],
	BRAKE: [KEY_S, -1, JOY_AXIS_TRIGGER_LEFT, 1.0],
	STEER_LEFT: [KEY_A, -1, JOY_AXIS_LEFT_X, -1.0],
	STEER_RIGHT: [KEY_D, -1, JOY_AXIS_LEFT_X, 1.0],
	CLUTCH: [KEY_SHIFT, JOY_BUTTON_A, -1, 0.0],
	SHIFT_UP: [KEY_E, JOY_BUTTON_RIGHT_SHOULDER, -1, 0.0],
	SHIFT_DOWN: [KEY_Q, JOY_BUTTON_LEFT_SHOULDER, -1, 0.0],
	IGNITION: [KEY_G, JOY_BUTTON_B, -1, 0.0],
	HANDBRAKE: [KEY_SPACE, JOY_BUTTON_X, -1, 0.0],
	TOGGLE_TC: [KEY_T, JOY_BUTTON_Y, -1, 0.0],
}


## Returns the default input events of [param action].
static func default_events(action: StringName) -> Array[InputEvent]:
	var binding = DEFAULTS[action]
	var events: Array[InputEvent] = []

	var key := InputEventKey.new()
	key.physical_keycode = binding[0]
	events.append(key)

	if binding[1] >= 0:
		var button := InputEventJoypadButton.new()
		button.button_index = binding[1]
		events.append(button)

	if binding[2] >= 0:
		var axis := InputEventJoypadMotion.new()
		axis.axis = binding[2]
		axis.axis_value = binding[3]
		events.append(axis)

	for event in events:
		event.device = -1 # all devices
	
	return events


## Adds every action that is missing from the [InputMap] with its default
## events. Called by the car when it enters the scene tree.
static func ensure_actions() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for event in default_events(action):
			InputMap.action_add_event(action, event)
