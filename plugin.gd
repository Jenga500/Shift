## Editor plugin of the Shift vehicle addon.
##
## When enabled it adds the input actions the car needs to the project's Input
## Map (only those that do not exist yet). The car node itself is the global
## class [code]ShiftCar[/code], so it shows up in the Create Node dialog without
## registering a custom type.
@tool
extends EditorPlugin


func _enable_plugin() -> void:
	var added := []
	for action in ShiftInput.DEFAULTS:
		var setting = "input/" + action
		if ProjectSettings.has_setting(setting):
			continue
		ProjectSettings.set_setting(setting, {
			"deadzone": ShiftInput.DEADZONE,
			"events": ShiftInput.default_events(action),
		})
		added.append(action)

	if not added.is_empty():
		ProjectSettings.save()
		print("Shift Vehicle: added input actions ", ", ".join(added), ". If they do not show in Project Settings > Input Map yet, restart the editor.")
