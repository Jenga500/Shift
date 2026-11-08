## Engine, clutch and drivetrain torque simulation for a vehicle.
##
## This script runs the powertrain half of a vehicle simulation each physics
## frame. It does not own any state itself; everything it reads and writes
## lives in the shared runtime data objects and the tuning [Resource] that are
## passed in.
##
## [b]Pipeline (see [method motor_process]):[/b][br]
## 0. Handle the ignition (starter, engine on/off), warm-up, idle control and
## effective throttle (see [method motor_input_process], once per frame).[br]
## 1. Count how many wheels receive engine torque.[br]
## 2. Compute the torque the engine produces from the throttle and torque curve.[br]
## 3. Compute internal engine friction.[br]
## 4. Compute the torque transferred through the clutch.[br]
## 5. Integrate engine angular velocity and derive RPM.[br]
## 6. Convert clutch torque to wheel torque and split it between wheels
## (center split for AWD, then open / Torsen / clutch-type LSD per axle).
##
## [b]Units:[/b] torque in N·m, angular velocity in rad/s, inertia in kg·m²,
## RPM in revolutions per minute, [code]delta[/code] in seconds.
##
## [b]Driver controls used[/b] ([code]RuntimeData.controls[/code]): [code]gas[/code]
## (throttle, 0..1) and [code]ignition[/code] (toggles the engine on and off). The clutch position
## is read from [code]EngineData.clutch_input[/code], which the transmission
## script sets (0..1, where 1 is fully pressed/disengaged).
##
## [b]Wheel index order[/b] used by all per-wheel arrays: 0 = front left (FL),
## 1 = front right (FR), 2 = rear left (RL), 3 = rear right (RR).
extends Node


## Handles the driver side of the engine: ignition and starter, warm-up and the
## effective throttle (gas pedal plus idle control).
##
## Call this once per physics frame, before the substeps of
## [method motor_process]. It reads one-shot requests (ignition), so it must not run
## more than once per frame.
func motor_input_process(delta: float, EngineData: RuntimeData.engine, AssistsData: RuntimeData.assists, Controls: RuntimeData.controls, Values: Resource) -> void:
	
	ignition_calc(EngineData, Controls, Values, delta)
	engine_warmth_calc(EngineData, Values, delta)
	throttle_calc(EngineData, AssistsData, Controls, Values)


## Runs one simulation step of the engine and drivetrain model.
##
## Call this once per simulation substep, after [method motor_input_process]
## ran for the frame. It updates [param EngineData] in place:
## [code]engine_driven_count[/code], [code]engine_torque[/code],
## [code]clutch_torque_on_engine[/code], [code]engine_angular_velocity[/code],
## [code]engine_rpm[/code] and [code]wheel_engine_torque[/code].
## [param TransmissionData] and [param WheelData] are only read.
##
## [param delta] is the time step in seconds.[br]
## [param EngineData] is the runtime engine state (read and written).[br]
## [param TransmissionData] is the runtime gearbox state (current gear, gear
## ratio, shifting flag).[br]
## [param WheelData] is the runtime wheel state (angular velocities, slip
## ratios and tire forces).[br]
## [param BrakeData] is the runtime brake state (brake torques, for the clutch
## lock calculation).[br]
## [param Values] is the vehicle tuning resource (torque curve, inertias,
## final drive, differential type and so on).
##
func motor_process(delta: float, EngineData: RuntimeData.engine, TransmissionData: RuntimeData.transmission, WheelData: RuntimeData.wheels, BrakeData: RuntimeData.brake, Values: Resource) -> void:
	
	# driven count calc
	
	driven_count_calc(Values, EngineData)
	
	# engine torque calculation
	
	engine_torque_calc(EngineData, Values)
	
	# engine friciton calculation
	
	engine_friction_calc(EngineData, Values)
	
	# clutch torque calculation
		
	clutch_torque_calc(TransmissionData, WheelData, EngineData, BrakeData, Values, delta)
			
	# engine rpm calculation

	engine_rpm_calc(EngineData, Values, delta)
	
	# engine stalling
	
	engine_stall_calc(EngineData, Values)
	
	#Torque division (lsds, open diff)
	
	wheel_torque_divison(TransmissionData, EngineData, WheelData, Values)
	

## Handles the [code]ignition[/code] control and the starter.
##
## Pressing Ignition while the engine is off starts cranking: the starter runs
## for [code]starter_crank_time[/code] seconds, then the engine runs. Pressing it
## while the engine is running or cranking switches the engine off.
func ignition_calc(EngineData: RuntimeData.engine, Controls: RuntimeData.controls, Values: Resource, delta: float):
	
	if Controls.ignition:
		if EngineData.engine_running or EngineData.engine_starting:
			EngineData.engine_running = false
			EngineData.engine_starting = false
		else:
			EngineData.engine_starting = true
			EngineData.engine_stalled = false
			EngineData.starter_timer = Values.starter_crank_time
	
	if EngineData.engine_starting:
		EngineData.starter_timer -= delta
		if EngineData.starter_timer <= 0.0:
			EngineData.engine_starting = false
			EngineData.engine_running = true


## Warms the engine up while it runs and cools it down while it is off, and sets
## the idle target RPM from the warmth.
##
## A running engine warms up in [code]warmup_time[/code] seconds at idle, faster
## at higher RPM. The idle target goes from [code]cold_idle_rpm[/code] (cold) to
## [code]idle_rpm[/code] (warm).
func engine_warmth_calc(EngineData: RuntimeData.engine, Values: Resource, delta: float):
	
	if EngineData.engine_running:
		var rpm_factor = maxf(EngineData.engine_rpm / Values.idle_rpm, 1.0)
		EngineData.engine_warmth += delta / maxf(Values.warmup_time, 0.001) * rpm_factor
	else:
		EngineData.engine_warmth -= delta / maxf(Values.cooldown_time, 0.001)
	
	EngineData.engine_warmth = clampf(EngineData.engine_warmth, 0.0, 1.0)
	EngineData.idle_target_rpm = lerpf(Values.cold_idle_rpm, Values.idle_rpm, EngineData.engine_warmth)


## Sets the effective throttle [code]EngineData.throttle[/code].
##
## It is the [code]gas[/code] control or the idle control, whichever is larger.
## The idle control opens the throttle in proportion to how far the RPM is below
## the idle target, up to [code]idle_throttle_max[/code]. Traction control
## scales the gas pedal by [code]AssistsData.tc_throttle[/code], but never below
## the idle control, so it cannot stall the engine. When the engine is off
## the throttle is 0.0, so it produces no torque.
func throttle_calc(EngineData: RuntimeData.engine, AssistsData: RuntimeData.assists, Controls: RuntimeData.controls, Values: Resource):
	
	if not EngineData.engine_running:
		EngineData.throttle = 0.0
		return
	
	var idle_throttle = clampf((EngineData.idle_target_rpm - EngineData.engine_rpm) / 300.0, 0.0, 1.0) * Values.idle_throttle_max
	EngineData.throttle = maxf(clampf(Controls.gas, 0.0, 1.0) * AssistsData.tc_throttle, idle_throttle)


## Stalls the engine when it drops below [code]stall_rpm[/code] while the clutch
## is loading it. Does nothing when [code]stall_rpm[/code] is 0.0.
func engine_stall_calc(EngineData: RuntimeData.engine, Values: Resource):
	
	if not EngineData.engine_running or Values.stall_rpm <= 0.0:
		return
	if EngineData.engine_rpm < Values.stall_rpm and absf(EngineData.clutch_torque_on_engine) > 0.0:
		EngineData.engine_running = false
		EngineData.engine_stalled = true


## Counts how many wheels are driven by the engine and stores the result in
## [code]EngineData.engine_driven_count[/code].
##
## A wheel counts as driven when [code]Values.driven_wheels()[/code] (from the
## drive type) marks it.
func driven_count_calc(Values: Resource, EngineData: RuntimeData.engine):
	
	var driven_wheels = Values.driven_wheels()
	var driven_count = 0

	for i in range(4):
		if driven_wheels[i]:
			driven_count += 1

	EngineData.engine_driven_count = driven_count


## Sums the angular velocities of all driven wheels.
##
## Only wheels flagged as driven in [param Values] contribute. Divide the
## result by the driven wheel count to get the average driven wheel speed.
## Reads [code]WheelData.wheel_angular_velocity[/code].
##
## Returns the sum of driven wheel angular velocities in rad/s.
func angular_velocity_sum_calc(WheelData: RuntimeData.wheels, Values: Resource):
	
	var driven_wheels = Values.driven_wheels()

	var angular_velocity_sum: float = 0.0
	
	for i in range(4):
		if driven_wheels[i]:
			angular_velocity_sum += WheelData.wheel_angular_velocity[i]

	
	return angular_velocity_sum
	

## Calculates the torque the engine produces this frame and stores it in
## [code]EngineData.engine_torque[/code].
##
## The result is the torque curve sampled at the normalized RPM
## ([code]engine_rpm / max_rpm[/code]), scaled by [code]max_torque[/code] and by
## the effective throttle ([code]EngineData.throttle[/code]).
##
func engine_torque_calc(EngineData: RuntimeData.engine, Values: Resource):
	
	var throttle_input = EngineData.throttle
	
	var normalized_rpm = EngineData.engine_rpm / Values.max_rpm

	EngineData.engine_torque = Values.torque_curve.sample(normalized_rpm) * Values.max_torque * throttle_input
	

## Calculates the internal friction torque of the engine at its current RPM.
##
## Friction is modeled as a quadratic polynomial of the normalized RPM
## ([code]engine_rpm / max_rpm[/code]):
## [code]friction_c0 + friction_c1 * n + friction_c2 * n²[/code].
##
## Returns the friction torque in N·m.
##
## [b]Note:[/b] the returned value is currently discarded by
func engine_friction_calc(EngineData: RuntimeData.engine, Values: Resource):
	
	
	var normalized_rpm = EngineData.engine_rpm / Values.max_rpm
	var base_friction = Values.friction_c0                      
	var linear_friction = Values.friction_c1 * normalized_rpm       
	var quadratic_friction = Values.friction_c2 * normalized_rpm * normalized_rpm
	return base_friction + linear_friction + quadratic_friction
	
	
## Calculates the torque the clutch transfers between engine and drivetrain and
## stores it in [code]EngineData.clutch_torque_on_engine[/code].
##
## The clutch is modeled as a friction element with a torque limit. The
## function computes the lock torque: the clutch torque that makes the engine
## speed and the driven wheel speed (through the gearing) equal at the end of
## this step. It is solved together with everything else acting this step, the
## engine's own torque ([method engine_free_torque_calc]) and, on the wheel side,
## the tire force with its gradient and the brakes, the same way the wheel spin
## is integrated. So a fully engaged clutch really locks, at any step size. The
## result is clamped to what the clutch can transmit:
## [code]max_clutch_torque * (1 - clutch_input)[/code]. A fully pressed clutch
## pedal therefore transmits no torque, and a partially pressed pedal slips once
## the lock torque exceeds the limit.
##
## The reported torque is positive when the clutch is slowing the engine down
## (engine faster than the driveline).
##
## The clutch torque is set to zero, and no calculation is done, when:[br]
## - the gearbox is shifting,[br]
## - the current gear is [code]1[/code] (treated as neutral by this code),[br]
## - the total drivetrain ratio is effectively zero,[br]
## - no wheels are driven.
##
## [param delta] is the time step in seconds.
func clutch_torque_calc(TransmissionData: RuntimeData.transmission, WheelData: RuntimeData.wheels, EngineData: RuntimeData.engine, BrakeData: RuntimeData.brake, Values: Resource, delta: float):

	if TransmissionData.is_shifting or TransmissionData.current_gear == 1:
		EngineData.clutch_torque_on_engine = 0.0
		return

	var drivetrain_ratio = TransmissionData.current_gear_ratio * Values.final_drive
	if abs(drivetrain_ratio) < 0.0001:
		EngineData.clutch_torque_on_engine = 0.0
		return

	if EngineData.engine_driven_count <= 0:
		EngineData.clutch_torque_on_engine = 0.0
		return
	
	var clutch_input := 1.0 - EngineData.clutch_input
	var max_transferable_torque = Values.max_clutch_torque * clutch_input
	
	# average state of the driven wheels
	var driven_wheels = Values.driven_wheels()
	var driven_count = EngineData.engine_driven_count
	var wheel_angular_velocity = angular_velocity_sum_calc(WheelData, Values) / driven_count
	var wheel_resisting_torque := 0.0 # tire reaction and brakes
	var tire_gradient := 0.0
	for i in range(4):
		if driven_wheels[i]:
			wheel_resisting_torque += (WheelData.longitude_force[i] * Values.wheel_radius + BrakeData.wheel_brake_torque[i]) / driven_count
			tire_gradient += WheelData.longitude_force_gradient[i] / driven_count
	
	# speed change per N·m on each side this step (the wheel side includes the
	# tire's resistance to changing speed, as in the wheel spin integration)
	var engine_step = delta / Values.engine_inertia
	var wheel_step = delta / (Values.wheel_inertia + delta * Values.wheel_radius * tire_gradient)
	var wheel_share = drivetrain_ratio * Values.drive_train_efficeny / driven_count # wheel torque per N·m of clutch torque
	
	# solve: engine speed after the step == drivetrain_ratio * wheel speed after the step
	var lock_torque = (EngineData.engine_angular_velocity + engine_free_torque_calc(EngineData, Values) * engine_step \
		- drivetrain_ratio * (wheel_angular_velocity - wheel_resisting_torque * wheel_step)) \
		/ (engine_step + drivetrain_ratio * wheel_share * wheel_step)
	
	EngineData.clutch_torque_on_engine = clampf(lock_torque, -max_transferable_torque, max_transferable_torque)


## Returns the net torque on the engine without the clutch, in N·m: the
## combustion torque plus the starter, minus the friction (scaled down with the
## throttle opening).
##
## While the starter cranks, the starter torque is added until the engine
## reaches [code]starter_rpm[/code]. At or above [code]max_rpm[/code] the
## combustion torque is cut (rev limiter), leaving the full friction, so the RPM
## drops back below the limit.
func engine_free_torque_calc(EngineData: RuntimeData.engine, Values: Resource) -> float:
	
	var engine_friction = engine_friction_calc(EngineData, Values)
	
	if EngineData.engine_angular_velocity >= Values.max_rpm * TAU / 60.0:
		return -engine_friction
	
	var starter_torque = 0.0
	if EngineData.engine_starting:
		starter_torque = Values.starter_torque * clampf((Values.starter_rpm - EngineData.engine_rpm) / 100.0, 0.0, 1.0)
	
	return EngineData.engine_torque + starter_torque - ((1.0 - EngineData.throttle) * engine_friction)


## Integrates the engine's angular velocity and updates its RPM.
##
## Net torque is the engine's own torque ([method engine_free_torque_calc])
## minus the clutch torque acting on the engine. That torque is divided by
## [code]engine_inertia[/code] to get angular acceleration, which is integrated
## over [param delta].
##
## Negative angular velocity is clamped to zero, so the engine never spins
## backwards. [code]EngineData.engine_rpm[/code] is derived from the new angular
## velocity with [code]rpm = ω * 60 / TAU[/code].
func engine_rpm_calc(EngineData: RuntimeData.engine, Values: Resource, delta: float):
	
	var net_engine_torque = engine_free_torque_calc(EngineData, Values) - EngineData.clutch_torque_on_engine
	
	var engine_angular_accel = net_engine_torque / Values.engine_inertia
	EngineData.engine_angular_velocity += engine_angular_accel * delta

	# clamped after integrating so a switched off engine rests at exactly 0 RPM
	if EngineData.engine_angular_velocity < 0.0:
		EngineData.engine_angular_velocity = 0.0

	EngineData.engine_rpm = EngineData.engine_angular_velocity * 60.0 / TAU
		

## Unfinished.
func wheel_torque_divison(TransmissionData: RuntimeData.transmission, EngineData: RuntimeData.engine, WheelData: RuntimeData.wheels, Values: Resource):
	var driven_wheels = Values.driven_wheels()
	var drivetrain_ratio = TransmissionData.current_gear_ratio * Values.final_drive

	var torque_at_wheels = EngineData.clutch_torque_on_engine * drivetrain_ratio * Values.drive_train_efficeny

	# finding axle usage (refuses abnormal configurations, more info in values.gd)

	var front_driven = driven_wheels[0] and driven_wheels[1]
	var rear_driven = driven_wheels[2] and driven_wheels[3]

	var do_front = false
	var do_rear = false

	if front_driven and rear_driven:
		do_front = true
		do_rear = true
	elif front_driven:
		do_front = true
	elif rear_driven:
		do_rear = true
	else:
		var per_wheel_torque = torque_at_wheels / EngineData.engine_driven_count if EngineData.engine_driven_count > 0 else 0.0
		for i in range(4):
			EngineData.wheel_engine_torque[i] = per_wheel_torque if driven_wheels[i] else 0.0

	var both_driven = do_front and do_rear

	for axle_index in range(2):
		var active = do_front if axle_index == 0 else do_rear
		if not active:
			continue

		var idx_a = 0 if axle_index == 0 else 2
		var idx_b = 1 if axle_index == 0 else 3

		# awd behavior

		var axle_torque: float
		if both_driven:
			axle_torque = torque_at_wheels * Values.center_diff_split if axle_index == 0 else torque_at_wheels * (1.0 - Values.center_diff_split)
		else:
			axle_torque = torque_at_wheels

		# variable definitions

		var slip_a = WheelData.slip_ratio[idx_a]
		var slip_b = WheelData.slip_ratio[idx_b]

		var T_lock: float
		var T_high: float
		var T_low: float

		# type of lsd or open diff

		if Values.differential == Values.DiffType.TORSEN_LSD:
			if min(slip_a, slip_b) <= 0.0:
				T_high = axle_torque / 2.0
				T_low  = axle_torque / 2.0
			else:
				T_high = axle_torque * (Values.TBR / (Values.TBR + 1.0))
				T_low  = axle_torque * (1.0 / (Values.TBR + 1.0))
		elif Values.differential == Values.DiffType.CLUTCH_LSD:
			var sign_val: float = 1.0 if axle_torque >= 0.0 else -1.0
			var abs_axle: float = abs(axle_torque)
			T_lock = Values.minimum_clutch_lsd_force + (abs_axle * Values.clutch_lsd_ramp_factor)
			T_lock = min(T_lock, abs_axle / 2.0)
			T_high = sign_val * ((abs_axle / 2.0) + T_lock)
			T_low  = sign_val * max((abs_axle / 2.0) - T_lock, 0.0)
		elif Values.differential == Values.DiffType.ELECTRONIC_LSD:
			pass # will write logic
		elif Values.differential == Values.DiffType.OPEN:
			T_high = axle_torque / 2.0
			T_low  = axle_torque / 2.0

		# actual torque division

		var diff = slip_a - slip_b
		if diff > Values.SLIP_THRESHOLD:
			EngineData.wheel_engine_torque[idx_a] = T_low
			EngineData.wheel_engine_torque[idx_b] = T_high
		elif -diff > Values.SLIP_THRESHOLD:
			EngineData.wheel_engine_torque[idx_a] = T_high
			EngineData.wheel_engine_torque[idx_b] = T_low
		else:
			EngineData.wheel_engine_torque[idx_a] = axle_torque / 2.0
			EngineData.wheel_engine_torque[idx_b] = axle_torque / 2.0
