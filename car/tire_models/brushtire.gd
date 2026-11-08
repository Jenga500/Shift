## Tire forces and wheel spin for one raycast wheel, using a brush tire model.
##
## Attach this script to each wheel's [RayCast3D]. It does two jobs:[br]
## - [b]Tire forces[/b] ([method _get_wheel_forces]): it measures how the tire
## slides over the ground (slip ratio and slip angle), turns that into a
## longitudinal (forward/back) and lateral (sideways) force with the brush model,
## and applies the result to the car's [RigidBody3D] at the contact point.[br]
## - [b]Wheel spin[/b] ([method _get_wheel_angular_velocity]): it integrates the
## wheel's angular velocity from the engine torque, brake torque, the reaction
## of the ground force and rolling resistance.
##
## It keeps no state of its own: everything is stored in the shared wheel
## runtime data, and the settings come from the car tuning resource. The load on
## the tire comes from the suspension script, so that must run first.
##
## [b]Brush model summary:[/b] the slip stiffness [code]brush_Csx[/code] (longitudinal)
## and [code]brush_Csy[/code] (lateral) turn the slip ratio and slip angle into a
## combined "slip force" [code]s[/code]. With the friction limit
## [code]μ·Fz[/code] (friction coefficient times normal load) and
## [code]θ = s / (3·μ·Fz)[/code], the total tire force is
## [code]μ·Fz·(3θ - 3θ² + θ³)[/code] for [code]θ ≤ 1[/code], and the saturated
## value [code]μ·Fz[/code] above that. The force is then split back into
## longitudinal and lateral parts in proportion to the slip force components.
##
## [b]Requirements:[/b][br]
## - The ray must have a [code]"wheel_index"[/code] meta value (0 = front left,
## 1 = front right, 2 = rear left, 3 = rear right).[br]
## - The ray's local axes define the tire direction: [code]-Z[/code] is forward
## (rolling direction), [code]X[/code] is sideways. For front wheels the ray must
## turn with the steering for the slip angle to be correct.[br]
## - The suspension runtime data must provide [code]wheel_spring_force[/code],
## which is used as the tire's normal load.
##
## [b]Units:[/b] meters, seconds, newtons, N·m, rad/s and kg·m².
extends RayCast3D


## Returns the velocity of the car body at a point in world space.
##
## This is the linear velocity of the body plus the velocity caused by its
## rotation at that point ([code]angular_velocity × offset[/code]), where the
## offset is measured from the body's origin.
##
## [param point] is the world-space position to evaluate.[br]
## [param car] is the rigid body.
##
## Returns the world-space velocity in m/s.
func _get_point_velocity(point: Vector3, car: RigidBody3D) -> Vector3:
	return car.linear_velocity + car.angular_velocity.cross(point - car.global_position)


## Calculates the tire forces for one wheel.
##
## Call this once per simulation substep for each wheel. It always updates the
## basic measurements ([method core_values_calc]). If the wheel is not touching
## the ground ([code]is_colliding()[/code] is false) it stops there. Otherwise it
## runs the full chain: slip, slip force, total force, force split into
## longitudinal and lateral, and finally the force vectors. The car script
## averages [code]combined_force_vector[/code] over the substeps of a physics
## frame and applies it to the body.
##
## [param wheel] is the wheel's raycast (normally this node).[br]
## [param WheelData] is the runtime wheel state (read and written).[br]
## [param SuspensionData] is the runtime suspension state, read for the normal
## load.[br]
## [param car] is the car body that the force acts on.[br]
## [param Values] is the car tuning resource.
func _get_wheel_forces(wheel: RayCast3D, WheelData: RuntimeData.wheels, SuspensionData: RuntimeData.suspension, car: RigidBody3D, Values: Resource):
	
	var wheel_index = wheel.get_meta("wheel_index")
	
	core_values_calc(wheel, WheelData, car, wheel_index, Values, SuspensionData)

	if not wheel.is_colliding():
		return

	slip_calc(WheelData, wheel_index)
	slip_force_calc(WheelData, wheel_index, Values)
	total_force_calc(WheelData, wheel_index, Values)
	force_gradient_calc(WheelData, wheel_index, Values)
	force_split_calc(WheelData, wheel_index)
	force_vector_calc(wheel, WheelData, wheel_index, car)


## Measures the speeds and the load that the rest of the tire model needs.
##
## Sets these fields on [param WheelData]:[br]
## - [code]side_velocity[/code]: the car's velocity at the wheel along the wheel's
## sideways axis (local X), in m/s.[br]
## - [code]forward_speed[/code]: the car's velocity at the wheel along the wheel's
## forward axis (local -Z), in m/s.[br]
## - [code]wheel_surface_speed[/code]: how fast the tire's surface moves, which is
## [code]wheel_angular_velocity * wheel_radius[/code], in m/s.[br]
## - [code]normal_load[i][/code]: the tire's load, taken as the length of the
## wheel's spring force vector from the suspension, in N.
func core_values_calc(wheel: RayCast3D, WheelData: RuntimeData.wheels, car: RigidBody3D, wheel_index: int, Values: Resource, SuspensionData: RuntimeData.suspension):
	
	var velocity_at_wheel = _get_point_velocity(wheel.global_position, car)
	WheelData.side_velocity = velocity_at_wheel.dot(wheel.global_transform.basis.x.normalized())
	WheelData.forward_speed = velocity_at_wheel.dot(-wheel.global_transform.basis.z.normalized())
	WheelData.wheel_surface_speed = WheelData.wheel_angular_velocity[wheel_index] * Values.wheel_radius
	WheelData.normal_load[wheel_index] = SuspensionData.wheel_spring_force[wheel_index].length()
	WheelData.ground_speed[wheel_index] = WheelData.forward_speed


## Calculates the slip angle and slip ratio of one wheel.
##
## [b]Slip angle[/b]: the angle between where the tire points and where it is
## moving, [code]-atan(side_velocity / |forward_speed|)[/code], in radians. The
## sign is negated so that the resulting lateral force opposes the sideways
## sliding.[br]
## [b]Slip ratio[/b]: how much faster (positive) or slower (negative) the tire
## surface moves than the car over the ground,
## [code](surface_speed - forward_speed) / |forward_speed|[/code].
##
## Results are stored in [code]slip_angle[i][/code] and [code]slip_ratio[i][/code].
##
func slip_calc(WheelData: RuntimeData.wheels, wheel_index: int):
	
	if abs(WheelData.forward_speed) < 0.001:
		WheelData.slip_angle[wheel_index] = 0.0
		WheelData.slip_ratio[wheel_index] = 0.0
	else:
		WheelData.slip_angle[wheel_index] = -(atan(WheelData.side_velocity / abs(WheelData.forward_speed)))
		WheelData.slip_ratio[wheel_index] = (WheelData.wheel_surface_speed - WheelData.forward_speed) / abs(WheelData.forward_speed)


## Converts the slip into force values with the tire slip stiffness (the
## linear part of the brush model).
##
## Sets these fields on [param WheelData], all in newtons:[br]
## - [code]slip_force_x[i][/code]: [code]brush_Csx * slip_ratio[/code]
## (longitudinal).[br]
## - [code]slip_force_y[i][/code]: [code]brush_Csy * tan(slip_angle)[/code]
## (lateral).[br]
## - [code]s_combined[i][/code]: the length of the two, [code]√(x² + y²)[/code].
##
## These are the forces the tire would produce if it had unlimited grip.
## [method total_force_calc] then limits them by the available friction.
func slip_force_calc(WheelData: RuntimeData.wheels, wheel_index: int, Values: Resource):
	
	var sx = Values.brush_Csx * WheelData.slip_ratio[wheel_index]
	var sy = Values.brush_Csy * tan(WheelData.slip_angle[wheel_index])

	WheelData.slip_force_x[wheel_index] = sx
	WheelData.slip_force_y[wheel_index] = sy
	WheelData.s_combined[wheel_index] = sqrt(sx * sx + sy * sy)


## Calculates the total tire force with the brush model's friction limit.
##
## The friction coefficient is [code]brush_mu[/code] times the grip of the
## surface under the wheel ([ShiftSurface]). Once the whole contact patch
## slides ([code]theta > 1[/code]), it falls towards [code]brush_mu_slide[/code]
## of that value the faster the patch slides beyond that point (sliding
## friction), with [code]1 - exp(-extra_sliding_speed / brush_slide_speed)[/code].
## So a spinning, locked or drifting tire has less grip than one that just
## rolls, while normal cornering and braking (gripping, partly sliding patch)
## keep the full grip.[br]
## The friction limit is that coefficient times [code]normal_load[/code] and is stored in
## [code]friction_limit[i][/code]. The normalized slip is
## [code]theta = s_combined / (3 * friction_limit)[/code], stored in
## [code]theta[i][/code], and the force is stored in [code]total_force[i][/code]:[br]
## - [code]theta ≤ 1[/code] (the tire is gripping, partly sliding):
## [code]μFz * (3θ - 3θ² + θ³)[/code], which rises smoothly up to the limit.[br]
## - [code]theta > 1[/code] (the tire slides fully): [code]μFz[/code], the
## limit.
##
## When the friction limit is almost zero (below 0.001 N, for example when the
## wheel has no load) [code]theta[/code] is set to 0.0 and so no force is produced.
##
## The result is the size of the combined force, in newtons. It has no direction
## yet. [method force_split_calc] provides that.
## Calculates how fast the longitudinal force grows with the wheel's angular
## velocity and stores it in [code]longitude_force_gradient[i][/code].
##
## The brush curve's slope is [code](1 - θ)²[/code] times the slip stiffness,
## and the slip ratio changes by [code]wheel_radius / |forward speed|[/code] per
## rad/s, so the gradient is [code](1 - θ)² · Csx · r / |v|[/code]. It is 0.0 when
## the tire is sliding (θ ≥ 1) or the wheel is not moving over the ground.
func force_gradient_calc(WheelData: RuntimeData.wheels, wheel_index: int, Values: Resource):
	
	var speed = absf(WheelData.forward_speed)
	var theta = WheelData.theta[wheel_index]
	if speed < 0.001 or theta >= 1.0:
		WheelData.longitude_force_gradient[wheel_index] = 0.0
	else:
		WheelData.longitude_force_gradient[wheel_index] = (1.0 - theta) * (1.0 - theta) * Values.brush_Csx * Values.wheel_radius / speed


func total_force_calc(WheelData: RuntimeData.wheels, wheel_index: int, Values: Resource):
	
	var surface = WheelData.surface[wheel_index]
	var grip: float = surface.grip if surface else 1.0
	var mu = Values.brush_mu * grip
	
	# sliding friction, only once the whole contact patch slides
	var static_limit = mu * WheelData.normal_load[wheel_index]
	if static_limit > 0.001 and WheelData.s_combined[wheel_index] > 3.0 * static_limit:
		var sliding_speed = Vector2(WheelData.wheel_surface_speed - WheelData.forward_speed, WheelData.side_velocity).length()
		var extra_sliding_speed = sliding_speed * (1.0 - 3.0 * static_limit / WheelData.s_combined[wheel_index])
		var slide = 1.0 - exp(-extra_sliding_speed / maxf(Values.brush_slide_speed, 0.01))
		mu *= lerpf(1.0, Values.brush_mu_slide, slide)
	
	WheelData.friction_limit[wheel_index] = mu * WheelData.normal_load[wheel_index]
	var mu_Fz = WheelData.friction_limit[wheel_index]
	if mu_Fz > 0.001:
		WheelData.theta[wheel_index] = WheelData.s_combined[wheel_index] / (3.0 * mu_Fz)
	else:
		WheelData.theta[wheel_index] = 0.0

	var theta = WheelData.theta[wheel_index]

	if theta <= 1.0:
		WheelData.total_force[wheel_index] = mu_Fz * (3.0 * theta - 3.0 * theta * theta + theta * theta * theta)
	else:
		WheelData.total_force[wheel_index] = mu_Fz


## Splits the total tire force into a longitudinal and a lateral part.
##
## The total force is distributed in proportion to the two slip force components:
## [code]longitude_force = total * slip_force_x / s_combined[/code] and
## [code]lateral_force = total * slip_force_y / s_combined[/code]. This keeps the
## combined force inside the friction limit, so using up grip for braking or
## acceleration automatically reduces the grip available for cornering and
## vice versa (the "friction circle").
##
## Results are stored in [code]longitude_force[i][/code] and
## [code]lateral_force[i][/code] in newtons. Both are set to 0.0 when
## [code]s_combined[/code] is almost zero (below 0.0001), to avoid dividing by zero.
func force_split_calc(WheelData: RuntimeData.wheels, wheel_index: int):
	var s_combined = WheelData.s_combined[wheel_index]

	if s_combined > 0.0001:
		var F_total = WheelData.total_force[wheel_index]
		WheelData.longitude_force[wheel_index] = F_total * (WheelData.slip_force_x[wheel_index] / s_combined)
		WheelData.lateral_force[wheel_index] = F_total * (WheelData.slip_force_y[wheel_index] / s_combined)
	else:
		WheelData.longitude_force[wheel_index] = 0.0
		WheelData.lateral_force[wheel_index] = 0.0


## Turns the force values into world-space vectors and applies them to the car.
##
## The longitudinal force acts along the wheel's forward direction (local -Z) and
## the lateral force along its sideways axis (local X). Both vectors and their sum
## are stored in [code]longitude_force_vector[i][/code],
## [code]lateral_force_vector[i][/code] and [code]combined_force_vector[i][/code]
## (for example for debug arrows).
##
## The force is not applied here; the car script applies the average over all
## substeps at the ground contact point once per physics frame.
func force_vector_calc(wheel: RayCast3D, WheelData: RuntimeData.wheels, wheel_index: int, car: RigidBody3D):
	WheelData.longitude_force_vector[wheel_index] = WheelData.longitude_force[wheel_index] * -wheel.global_transform.basis.z.normalized()
	WheelData.lateral_force_vector[wheel_index] = WheelData.lateral_force[wheel_index] * wheel.global_transform.basis.x.normalized()
	WheelData.combined_force_vector[wheel_index] = WheelData.longitude_force_vector[wheel_index] + WheelData.lateral_force_vector[wheel_index]
	

## Updates the spin speed of one wheel.
##
## Call this once per physics frame for each wheel, after the engine, brake and
## tire force scripts have run, because it reads their results.
##
## [b]In the air[/b] (not colliding): the net torque is the engine torque minus the
## brake torque. The brake torque always opposes the current spin direction (it
## uses the sign of the angular velocity, so it does nothing when the wheel is
## stopped). A drag torque that grows with the spin speed
## ([code]0.001 * |ω|[/code], hard coded) slows the wheel. The speed is
## integrated implicitly,
## [code]ω = (ω + τ/I · dt) / (1 + drag/I · dt)[/code], which stays stable.[br]
## [b]On the ground[/b] (colliding): the net torque is the engine torque minus the
## brake torque, minus the reaction to the tire's longitudinal force
## ([code]longitude_force * wheel_radius[/code]), minus rolling resistance
## ([code]rolling_resistance_coeff * normal_force * wheel_radius[/code], times
## the rolling resistance of the surface ([ShiftSurface]), opposing the spin). The angular velocity changes by [code]net_torque / wheel_inertia * delta[/code].
##
## On the ground the tire force is integrated semi-implicitly: the force is
## treated as falling with [code]longitude_force_gradient[/code] as the wheel
## approaches zero slip, and it may pull the wheel to zero slip but not past it.
## This keeps the stiff wheel/tire loop stable at any time step. The tire force
## the wheel actually used this step is written back to
## [code]longitude_force[i][/code] and the force vectors, so the body receives
## the same force.
##
## When the brake is applied and the wheel has been driven below zero speed, the
## angular velocity is set to 0.0. So the brakes can stop the wheel but never
## make it spin backward.
##
## [param wheel] is the wheel's raycast.[br]
## [param delta] is the time step in seconds.[br]
## [param WheelData] is the runtime wheel state ([code]wheel_angular_velocity[/code]
## is updated).[br]
## [param EngineData] provides [code]wheel_engine_torque[/code].[br]
## [param BrakeData] provides [code]wheel_brake_torque[/code].[br]
## [param SuspensionData] provides [code]wheel_spring_force[/code] for the rolling
## resistance.[br]
## [param Values] is the car tuning resource.
func _get_wheel_angular_velocity(wheel: RayCast3D, delta: float, WheelData: RuntimeData.wheels, EngineData: RuntimeData.engine, BrakeData: RuntimeData.brake, SuspensionData: RuntimeData.suspension, Values: Resource):
	var wheel_index: int = wheel.get_meta("wheel_index")
	var net_torque: float

	# in air behavior

	if not wheel.is_colliding():

		var brake_torque: float = BrakeData.wheel_brake_torque[wheel_index] * signf(WheelData.wheel_angular_velocity[wheel_index])
		var air_drag_coeff: float = 0.001 * absf(WheelData.wheel_angular_velocity[wheel_index])

		net_torque = EngineData.wheel_engine_torque[wheel_index] - brake_torque
		WheelData.wheel_angular_velocity[wheel_index] = (WheelData.wheel_angular_velocity[wheel_index] + (net_torque / Values.wheel_inertia) * delta) / (1.0 + (air_drag_coeff / Values.wheel_inertia) * delta)

	# on ground behavior

	else:
		var normal_force: float = SuspensionData.wheel_spring_force[wheel_index].length()
		var surface = WheelData.surface[wheel_index]
		var surface_resistance: float = surface.rolling_resistance if surface else 1.0
		var rolling_resistance: float = Values.rolling_resistance_coeff * surface_resistance * normal_force * Values.wheel_radius * signf(WheelData.wheel_angular_velocity[wheel_index])
		var ground_reaction_torque: float = WheelData.longitude_force[wheel_index] * Values.wheel_radius
		var radius: float = Values.wheel_radius
		var inertia: float = Values.wheel_inertia
		var omega: float = WheelData.wheel_angular_velocity[wheel_index]

		net_torque = EngineData.wheel_engine_torque[wheel_index] - BrakeData.wheel_brake_torque[wheel_index] - rolling_resistance
		var omega_free: float = omega + (net_torque / inertia) * delta # without the tire force

		# semi-implicit: the tire force falls as the wheel approaches zero slip
		var gradient: float = WheelData.longitude_force_gradient[wheel_index]
		var omega_new: float = omega + (net_torque - ground_reaction_torque) * delta / (inertia + delta * radius * gradient)

		# the tire can pull the wheel to zero slip, but not past it
		var omega_ground: float = WheelData.ground_speed[wheel_index] / radius
		if (omega_free - omega_ground) * (omega_new - omega_ground) < 0.0:
			omega_new = omega_ground

		# the tire force the wheel actually used, so the body gets the same force
		var tire_force: float = inertia * (omega_free - omega_new) / (delta * radius)
		WheelData.longitude_force[wheel_index] = tire_force
		WheelData.longitude_force_vector[wheel_index] = tire_force * -wheel.global_transform.basis.z.normalized()
		WheelData.combined_force_vector[wheel_index] = WheelData.longitude_force_vector[wheel_index] + WheelData.lateral_force_vector[wheel_index]

		if BrakeData.wheel_brake_torque[wheel_index] > 0.0 and omega_new < 0.0:
			omega_new = 0.0
		WheelData.wheel_angular_velocity[wheel_index] = omega_new
