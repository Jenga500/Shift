## Gearbox and clutch control: manual, clutchless and fully automatic.
##
## This script handles gear selection and the effective clutch position. The
## gear change mode comes from [code]transmission_mode[/code] in the car tuning
## resource:[br]
## - [b]MANUAL:[/b] the player can only change gear while the clutch pedal is
## (almost) fully pressed.[br]
## - [b]CLUTCHLESS:[/b] gears change without the clutch pedal. An automatic
## clutch opens during shifts and at low RPM, so the car can also pull away and
## stop without the pedal.[br]
## - [b]AUTOMATIC:[/b] ShiftUp/ShiftDown only select R, N and D. In D the gear is
## picked from the driveline RPM and the throttle, using the automatic clutch.[br]
## Each shift takes a short, slightly random amount of time, during which the
## gear ratio is zero so no torque passes through the gearbox. It keeps no state
## of its own: the current gear, ratio and shift state live in the transmission
## runtime data, and the gear ratios come from the car tuning resource.
##
## [b]Gear numbering[/b] matches the [code]gear_ratio[/code] array in the car
## tuning resource: index 0 is reverse, index 1 is neutral (ratio 0.0), and
## indices 2 and up are the forward gears (first gear is index 2).
##
## [b]Driver controls used[/b] ([code]RuntimeData.controls[/code]):
## [code]clutch[/code] (pedal, 0..1, where 1 is fully pressed),
## [code]shift_up[/code], [code]shift_down[/code] and [code]handbrake[/code]
## (only to open the automatic clutch and hold the automatic gear).
##
## [b]Runtime data fields used:[/b] [code]current_gear[/code],
## [code]current_gear_ratio[/code], [code]is_shifting[/code],
## [code]shift_timer[/code] and [code]auto_shift_cooldown[/code]. It also writes
## the engine's [code]clutch_input[/code], which the clutch calculation in the
## motor script reads.
extends Node


## Runs one step of the transmission simulation.
##
## Call this once per physics frame. It first checks the shift inputs and starts
## a shift if one is requested, then advances any shift that is in progress.
##
## [param delta] is the time step in seconds.[br]
## [param Data] is the runtime transmission state (read and written).[br]
## [param EngineData] is the runtime engine state ([code]clutch_input[/code] is
## written, the rest is read).[br]
## [param WheelData] is the runtime wheel state (only read).[br]
## [param Controls] is the driver's input this frame.[br]
## [param Values] is the car tuning resource that holds the
## [code]gear_ratio[/code] array and the transmission mode.
func transmission_process(delta: float, Data: RuntimeData.transmission, EngineData: RuntimeData.engine, WheelData: RuntimeData.wheels, Controls: RuntimeData.controls, Values: Resource):
	
	gear_change(Data, Controls, Values)
	auto_gear_select(Data, EngineData, WheelData, Controls, Values, delta)
	gear_ratio_change(Data, delta, Values)
	clutch_process(Data, EngineData, Controls, Values)
	

## Handles shift up and shift down requests from the player.
##
## No request is accepted while a shift is already in progress
## ([code]is_shifting[/code] is true). In MANUAL mode the clutch pedal must also
## be pressed more than 95 percent; the other modes do not need the clutch.
##
## In MANUAL and CLUTCHLESS mode, when [code]shift_up[/code] is requested and the
## current gear is below the highest gear (the last index of
## [code]gear_ratio[/code]), the gear goes up by one. When [code]shift_down[/code]
## is requested and the current gear is above 0 (reverse), the gear goes down by
## one. Because gears are consecutive indices, shifting passes through neutral
## between reverse and first gear.
##
## In AUTOMATIC mode the inputs only move between R (0), N (1) and D (first gear
## and up): ShiftUp goes R -> N -> D, ShiftDown goes D -> N -> R. The forward
## gear inside D is chosen by [method auto_gear_select].
##
## The gear number changes immediately, but the gear ratio is only applied when
## the shift finishes (see [method gear_ratio_change]).
func gear_change(Data: RuntimeData.transmission, Controls: RuntimeData.controls, Values: Resource):
	
	if Data.is_shifting:
		return
	if Values.transmission_mode == Values.TransmissionMode.MANUAL and Controls.clutch <= 0.95:
		return
	
	var shift_up = Controls.shift_up
	var shift_down = Controls.shift_down
	
	if Values.transmission_mode == Values.TransmissionMode.AUTOMATIC:
		if shift_up and Data.current_gear < 2:
			start_shift(Data, Data.current_gear + 1)
		elif shift_down and Data.current_gear > 0:
			start_shift(Data, 1 if Data.current_gear >= 2 else 0)
		return
	
	if shift_up and Data.current_gear < Values.gear_ratio.size() - 1:
		start_shift(Data, Data.current_gear + 1)
	elif shift_down and Data.current_gear > 0:
		start_shift(Data, Data.current_gear - 1)


## Selects [param gear] and starts a shift. [code]shift_timer[/code] gets a random
## duration between 0.15 and 0.25 seconds, which adds some natural variation to
## the shift time.
func start_shift(Data: RuntimeData.transmission, gear: int):
	
	Data.current_gear = gear
	Data.is_shifting = true
	Data.shift_timer = 0.15 + randf() * 0.1


## Picks the forward gear in AUTOMATIC mode while D is selected.
##
## The decision uses the driveline RPM (the engine speed the wheels would give
## with the clutch closed), so a slipping clutch at launch does not cause an
## early upshift. The upshift RPM goes from [code]auto_upshift_rpm_min[/code] at
## no throttle to [code]auto_upshift_rpm_max[/code] at full throttle, kept
## below the rev limiter. It also shifts up early, from
## [code]auto_upshift_rpm_min[/code] on, once the next gear gives more torque at
## the wheels (for torque curves that fall off well before
## [code]max_rpm[/code]). It shifts down when the RPM in the next lower gear
## would be below [code]auto_downshift_factor[/code] times the upshift RPM and
## that gear gives more torque at the wheels, which also gives a kickdown when
## the throttle is pressed hard. After each shift it waits
## [code]auto_shift_cooldown[/code] seconds. No shifts happen while the
## handbrake is pulled.
func auto_gear_select(Data: RuntimeData.transmission, EngineData: RuntimeData.engine, WheelData: RuntimeData.wheels, Controls: RuntimeData.controls, Values: Resource, delta: float):
	
	Data.auto_shift_cooldown = maxf(Data.auto_shift_cooldown - delta, 0.0)
	
	if Values.transmission_mode != Values.TransmissionMode.AUTOMATIC:
		return
	if Data.is_shifting or Data.current_gear < 2 or Data.auto_shift_cooldown > 0.0:
		return
	# hold the gear while the handbrake locks the wheels (drifting)
	if Controls.handbrake > 0.1:
		return
	
	# kept below the rev limiter, or an engine with a lower max_rpm never upshifts
	var upshift_rpm = minf(lerpf(Values.auto_upshift_rpm_min, Values.auto_upshift_rpm_max, EngineData.throttle), Values.max_rpm * 0.97)
	
	var rpm = driveline_rpm(Data.current_gear, WheelData, Values)
	var wheel_torque = gear_wheel_torque(Data.current_gear, WheelData, Values)
	var top_gear = Data.current_gear >= Values.gear_ratio.size() - 1
	
	if not top_gear and (rpm > upshift_rpm or (rpm > Values.auto_upshift_rpm_min and gear_wheel_torque(Data.current_gear + 1, WheelData, Values) > wheel_torque)):
		start_shift(Data, Data.current_gear + 1)
		Data.auto_shift_cooldown = Values.auto_shift_cooldown
	elif Data.current_gear > 2 and driveline_rpm(Data.current_gear - 1, WheelData, Values) < upshift_rpm * Values.auto_downshift_factor \
			and gear_wheel_torque(Data.current_gear - 1, WheelData, Values) > wheel_torque:
		start_shift(Data, Data.current_gear - 1)
		Data.auto_shift_cooldown = Values.auto_shift_cooldown


## Returns how much torque reaches the wheels in [param gear] at full throttle,
## relative to the other gears: the torque curve at that gear's driveline RPM
## times the gear ratio. 0.0 when the RPM would be over [code]max_rpm[/code].
func gear_wheel_torque(gear: int, WheelData: RuntimeData.wheels, Values: Resource) -> float:
	
	var normalized_rpm = driveline_rpm(gear, WheelData, Values) / Values.max_rpm
	if normalized_rpm > 1.0:
		return 0.0
	return Values.torque_curve.sample(maxf(normalized_rpm, 0.0)) * Values.gear_ratio[gear]


## Returns the engine RPM that the average driven wheel speed gives in
## [param gear] (with the clutch closed).
func driveline_rpm(gear: int, WheelData: RuntimeData.wheels, Values: Resource) -> float:
	
	var driven_wheels = Values.driven_wheels()
	var angular_velocity_sum := 0.0
	var driven_count := 0
	
	for i in range(4):
		if driven_wheels[i]:
			angular_velocity_sum += WheelData.wheel_angular_velocity[i]
			driven_count += 1
	
	if driven_count == 0:
		return 0.0
	
	return (angular_velocity_sum / driven_count) * Values.gear_ratio[gear] * Values.final_drive * 60.0 / TAU


## Updates the active gear ratio and finishes shifts that are in progress.
##
## While a shift is in progress ([code]is_shifting[/code] is true) the active
## ratio [code]current_gear_ratio[/code] is held at 0.0, so the gearbox
## transmits no torque, and [code]shift_timer[/code] counts down by
## [param delta]. When the timer reaches zero, the ratio of the newly selected
## gear is read from [code]Values.gear_ratio[/code] and [code]is_shifting[/code]
## is set back to false.
##
## Nothing happens when no shift is in progress, so [code]current_gear_ratio[/code]
## keeps its last value. This means its starting value (before the first shift)
## must be set elsewhere, for example in the runtime data defaults.
##
## [param delta] is the time step in seconds.
func gear_ratio_change(Data: RuntimeData.transmission, delta: float, Values: Resource):

	if Data.is_shifting:
		Data.current_gear_ratio = 0.0
		Data.shift_timer -= delta
		if Data.shift_timer <= 0.0:
			Data.current_gear_ratio = Values.gear_ratio[Data.current_gear]
			Data.is_shifting = false


## Sets the effective clutch position [code]EngineData.clutch_input[/code]
## (0 = engaged, 1 = fully pressed).
##
## In MANUAL mode it is the clutch pedal. In CLUTCHLESS and AUTOMATIC mode an
## automatic clutch is added on top of the pedal (the larger of the two wins):
## it is fully open during a shift and at or below the idle target RPM, and
## closes linearly up to [code]auto_clutch_engage_rpm[/code]. It also opens
## while the handbrake is pulled if [code]handbrake_opens_clutch[/code] is on. This lets the car
## pull away on throttle alone and keeps the engine from being dragged down
## when the car stops in gear.
func clutch_process(Data: RuntimeData.transmission, EngineData: RuntimeData.engine, Controls: RuntimeData.controls, Values: Resource):
	
	var clutch_pedal = Controls.clutch
	
	if Values.transmission_mode != Values.TransmissionMode.MANUAL:
		var engage_range = maxf(Values.auto_clutch_engage_rpm - EngineData.idle_target_rpm, 1.0)
		var engagement = clampf((EngineData.engine_rpm - EngineData.idle_target_rpm) / engage_range, 0.0, 1.0)
		clutch_pedal = maxf(clutch_pedal, 1.0 - engagement)
		if Data.is_shifting or (Values.handbrake_opens_clutch and Controls.handbrake > 0.1):
			clutch_pedal = 1.0
	
	EngineData.clutch_input = clutch_pedal
