extends Node


func abs_proccess(delta: float, AssistsData: RuntimeData.assists, BrakeData: RuntimeData.brake, WheelData: RuntimeData.wheels, Values: Resource) -> void:

	for i in range(4):
		if not Values.ABS:
			AssistsData.abs_active[i] = false
			BrakeData.abs_input_brake[i] = BrakeData.input_brake
			continue

		var slip = WheelData.slip_ratio[i]

		if AssistsData.abs_active[i]:
			if slip < Values.abs_slip_apply:   # wheel has recovered
				AssistsData.abs_active[i] = false
		elif slip > Values.abs_slip_release:     # wheel slipping too much
			AssistsData.abs_active[i] = true

		var target = BrakeData.input_brake
		if AssistsData.abs_active[i]:
			target *= Values.abs_pedal_target

		var current: float = BrakeData.abs_input_brake[i]
		var rate: float = Values.abs_rate_release if target < current else Values.abs_rate_apply
		BrakeData.abs_input_brake[i] = move_toward(current, target, rate * delta)
		
## Traction control: keeps the driven wheels from spinning up under power.
##
## For each driven wheel on the ground it measures the drive slip, the wheel
## surface speed over the ground speed in the direction the engine pushes,
## against at least [code]tc_min_speed[/code]. Above
## [code]tc_slip_threshold[/code]:[br]
## - the throttle share [code]tc_throttle[/code] closes at
## [code]tc_cut_rate[/code] per second (it opens again at
## [code]tc_recover_rate[/code] once no wheel spins), which the motor applies to
## the gas pedal next frame;[br]
## - the spinning wheel is braked with up to [code]tc_brake_torque[/code],
## growing with how far the slip is over the threshold, so the differential
## sends the torque to the wheel that grips.[br]
## [code]Controls.toggle_tc[/code] switches it on and off ([code]tc_on[/code]).
func tc_proccess(delta: float, AssistsData: RuntimeData.assists, EngineData: RuntimeData.engine, WheelData: RuntimeData.wheels, Controls: RuntimeData.controls, Values: Resource) -> void:
	if Controls.toggle_tc:
		AssistsData.tc_on = not AssistsData.tc_on
	
	var driven_wheels = Values.driven_wheels()
	var threshold = maxf(Values.tc_slip_threshold, 0.01)
	var spinning := false
	
	for i in range(4):
		var excess := 0.0
		if AssistsData.tc_on and driven_wheels[i] and WheelData.normal_load[i] > 0.0:
			excess = maxf(drive_slip(i, EngineData, WheelData, Values) - threshold, 0.0)
		spinning = spinning or excess > 0.0
		
		# brakes only hold forward spin, so reverse is left to the throttle cut
		var target_brake := 0.0
		if WheelData.wheel_angular_velocity[i] > 0.0:
			target_brake = Values.tc_brake_torque * clampf(excess / threshold, 0.0, 1.0)
		AssistsData.tc_brake_torque[i] = move_toward(AssistsData.tc_brake_torque[i], target_brake, Values.tc_brake_torque * 10.0 * delta)
	
	if not AssistsData.tc_on:
		AssistsData.tc_throttle = 1.0
	elif spinning:
		AssistsData.tc_throttle = maxf(AssistsData.tc_throttle - Values.tc_cut_rate * delta, 0.0)
	else:
		AssistsData.tc_throttle = minf(AssistsData.tc_throttle + Values.tc_recover_rate * delta, 1.0)
	
	AssistsData.tc_active = spinning or AssistsData.tc_throttle < 1.0


## Returns the slip ratio of wheel [param i] in the direction the engine drives
## it (positive when the engine spins it faster than the ground moves), or 0.0
## when the engine does not drive it.
func drive_slip(i: int, EngineData: RuntimeData.engine, WheelData: RuntimeData.wheels, Values: Resource) -> float:
	var ground_speed: float = WheelData.ground_speed[i]
	var surface_speed: float = WheelData.wheel_angular_velocity[i] * Values.wheel_radius
	var slip = (surface_speed - ground_speed) / maxf(absf(ground_speed), Values.tc_min_speed)
	return slip * signf(EngineData.wheel_engine_torque[i])


	
func stability_proccess() -> void:
	pass # for the future. seems i need to do more research.
