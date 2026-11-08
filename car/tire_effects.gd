## Tire marks and tire smoke for a vehicle.
##
## Both effects are driven by the sliding speed of each tire's contact patch:
## the difference between the wheel's surface speed and the ground speed along
## the wheel, combined with the sideways speed. So they appear when drifting,
## when the wheels spin up (burnout) and when they lock under braking.
## Below [code]effect_slip_start[/code] nothing is shown, at
## [code]effect_slip_full[/code] the effects are at full strength.
##
## [b]Tire marks:[/b] one [MultiMeshInstance3D] per car draws flat quads on the
## ground. Each quad is one segment of [code]tire_mark_segment_length[/code],
## laid from the previous contact point to the current one. The segments live in
## a ring buffer of [code]tire_mark_max_segments[/code], so only the new segment
## is written each frame and the oldest ones are reused when it is full. The
## node is [code]top_level[/code], so the marks stay where they were drawn.
##
## [b]Tire smoke:[/b] one [GPUParticles3D] per wheel at the contact point,
## emitting in world space. Its [code]amount_ratio[/code] follows the sliding
## strength.
##
## Settings are in the "Effects" group of [CarValues]; the colors, and whether
## a surface gets marks or smoke at all, come from the [ShiftSurface] under the
## wheel (dark marks and white smoke on asphalt, brown marks and dust on dirt).
extends Node

## Height of the marks above the ground, in meters, so they do not flicker with
## the ground surface.
const MARK_LIFT = 0.02
## Gaps between contact points longer than this (in meters) start a new mark
## instead of connecting, for example after a teleport.
const MAX_MARK_GAP = 2.0

## The [MultiMeshInstance3D] that draws all tire marks of the car.
var mark_instance: MultiMeshInstance3D
## Ring buffer position of the next tire mark segment.
var next_segment := 0
## Number of segments written so far, up to the buffer size.
var used_segments := 0
## Contact point where the current mark of each wheel (by wheel index) ends.
var last_point := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
## True while the wheel (by wheel index) is drawing a mark.
var marking := [false, false, false, false]
## Smoke emitters by wheel index.
var smoke := []


## Creates the tire mark mesh and the smoke emitters as children of [param car].
func setup(car: RigidBody3D, Values: Resource) -> void:
	if Values.tire_marks:
		mark_instance = make_marks(Values)
		car.add_child(mark_instance)
	if Values.tire_smoke:
		for i in range(4):
			var emitter = make_smoke(Values)
			car.add_child(emitter)
			smoke.append(emitter)


## Returns the tire mark node: a flat quad multimesh with per-segment colors.
func make_marks(Values: Resource) -> MultiMeshInstance3D:
	var quad = PlaneMesh.new()
	quad.size = Vector2.ONE

	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true # the segment colors are inspector (sRGB) colors
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	# without this the sky reflection makes dark marks lighter than the road
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.metallic_specular = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material

	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = Values.tire_mark_max_segments
	multimesh.visible_instance_count = 0

	var node = MultiMeshInstance3D.new()
	node.name = "TireMarks"
	node.multimesh = multimesh
	node.top_level = true
	node.global_transform = Transform3D.IDENTITY
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Returns one smoke emitter: soft billboard puffs that rise, grow and fade.
func make_smoke(Values: Resource) -> GPUParticles3D:
	var process = ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 60.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.inherit_velocity_ratio = 0.15
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.scale_min = 0.6
	process.scale_max = 1.0

	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(1.0, 1.0))
	var scale_texture = CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture

	# fade in quickly, then fade out over the lifetime
	var fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.1, Color.WHITE)
	var fade_texture = GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture

	# soft round puff
	var puff = Gradient.new()
	puff.set_color(0, Color.WHITE)
	puff.set_color(1, Color(1, 1, 1, 0))
	var puff_texture = GradientTexture2D.new()
	puff_texture.gradient = puff
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(0.5, 0.0)
	puff_texture.width = 64
	puff_texture.height = 64

	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = puff_texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	# soft edge where a puff cuts into the ground
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.6

	var quad = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = material

	var emitter = GPUParticles3D.new()
	emitter.name = "TireSmoke"
	emitter.process_material = process
	emitter.draw_pass_1 = quad
	emitter.amount = Values.tire_smoke_amount
	emitter.lifetime = Values.tire_smoke_lifetime
	emitter.local_coords = false
	emitter.emitting = false
	emitter.top_level = true
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 15, 40))
	return emitter


## Updates the marks and the smoke from the current wheel state. Call once per
## physics frame, after the tire forces were calculated.
func effects_process(car: RigidBody3D, WheelData: RuntimeData.wheels, Values: Resource) -> void:
	for wheel in car.wheels:
		var i: int = wheel.get_meta("wheel_index")
		var strength := 0.0
		var contact := Vector3.ZERO
		var normal := Vector3.UP

		if wheel.is_colliding() and WheelData.normal_load[i] > 0.0:
			contact = wheel.get_collision_point()
			normal = wheel.get_collision_normal()
			strength = slide_strength(car, wheel, contact, WheelData.wheel_angular_velocity[i], Values)

		var surface: ShiftSurface = WheelData.surface[i]
		if mark_instance:
			mark_process(i, strength if surface and surface.marks else 0.0, contact, normal, surface, Values)
		if not smoke.is_empty():
			smoke_process(smoke[i], strength if surface and surface.smoke else 0.0, contact, surface)


## Returns how strongly a tire slides, from 0.0 (below
## [code]effect_slip_start[/code]) to 1.0 (at [code]effect_slip_full[/code] or
## more), from the sliding speed of its contact patch.
func slide_strength(car: RigidBody3D, wheel: RayCast3D, contact: Vector3, wheel_angular_velocity: float, Values: Resource) -> float:
	var velocity = car.linear_velocity + car.angular_velocity.cross(contact - car.global_position)
	var forward = -wheel.global_transform.basis.z.normalized()
	var side = wheel.global_transform.basis.x.normalized()
	var surface_speed = wheel_angular_velocity * Values.wheel_radius
	var sliding_speed = Vector2(surface_speed - velocity.dot(forward), velocity.dot(side)).length()
	return clampf((sliding_speed - Values.effect_slip_start) / maxf(Values.effect_slip_full - Values.effect_slip_start, 0.01), 0.0, 1.0)


## Extends or ends the mark of wheel [param i]. A new segment is laid once the
## contact point moved [code]tire_mark_segment_length[/code] from the end of the
## mark; its color comes from [param surface] and its opacity follows
## [param strength].
func mark_process(i: int, strength: float, contact: Vector3, normal: Vector3, surface: ShiftSurface, Values: Resource) -> void:
	if strength <= 0.0:
		marking[i] = false
		return

	if not marking[i] or last_point[i].distance_to(contact) > MAX_MARK_GAP:
		marking[i] = true
		last_point[i] = contact
		return

	var along = contact - last_point[i]
	along -= normal * along.dot(normal) # keep the mark flat on the ground
	var length = along.length()
	if length < Values.tire_mark_segment_length:
		return

	var dir = along / length
	var basis = Basis(normal.cross(dir).normalized() * Values.tire_mark_width, normal, dir * length)
	var origin = last_point[i] + along * 0.5 + normal * MARK_LIFT
	var color = surface.mark_color
	color.a *= strength

	var multimesh = mark_instance.multimesh
	multimesh.set_instance_transform(next_segment, Transform3D(basis, origin))
	multimesh.set_instance_color(next_segment, color)
	next_segment = (next_segment + 1) % multimesh.instance_count
	used_segments = mini(used_segments + 1, multimesh.instance_count)
	multimesh.visible_instance_count = used_segments

	last_point[i] = last_point[i] + along


## Moves [param emitter] to the contact point and sets how much it emits. The
## smoke color follows the surface (smoke on asphalt, dust on loose ground);
## when it changes, puffs that are already in the air take the new color too.
func smoke_process(emitter: GPUParticles3D, strength: float, contact: Vector3, surface: ShiftSurface) -> void:
	emitter.global_position = contact
	emitter.emitting = strength > 0.0
	emitter.amount_ratio = strength
	if strength > 0.0 and emitter.process_material.color != surface.smoke_color:
		emitter.process_material.color = surface.smoke_color
