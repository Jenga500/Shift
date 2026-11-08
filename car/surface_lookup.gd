## Finds the ground surface ([ShiftSurface]) under each wheel.
##
## Runs once per physics frame, after the wheel rays were updated, and stores
## the result in [code]WheelData.surface[/code] (by wheel index). The tire model
## reads grip and rolling resistance from it, the tire effects the colors.
##
## Lookup order for a wheel that touches the ground:[br]
## 1. The metadata [code]shift_surface[/code] of the collider the ray hits.[br]
## 2. The nodes in the group [code]shift_surface_providers[/code], which must
## have a method [code]get_surface(point: Vector3, collider: Object) -> ShiftSurface[/code]
## returning null when the point is not theirs (see [ShiftTerrain3DSurfaces]).[br]
## 3. [code]default_surface[/code] of [CarValues], or asphalt if it is empty.[br]
## A wheel in the air keeps the surface it had last.
extends Node

## Group of the nodes that can tell the surface at a point.
const PROVIDER_GROUP = &"shift_surface_providers"
## Metadata name of a [ShiftSurface] on a collider.
const SURFACE_META = &"shift_surface"

## Asphalt, used when [code]default_surface[/code] is empty.
var fallback := ShiftSurface.new()


## Updates [code]WheelData.surface[/code] for all wheels of [param car].
func surface_process(car: RigidBody3D, WheelData: RuntimeData.wheels, Values: Resource) -> void:
	var default_surface: ShiftSurface = Values.default_surface if Values.default_surface else fallback
	var providers = car.get_tree().get_nodes_in_group(PROVIDER_GROUP)

	for wheel in car.wheels:
		var i: int = wheel.get_meta("wheel_index")
		if WheelData.surface[i] == null:
			WheelData.surface[i] = default_surface
		if not wheel.is_colliding():
			continue
		WheelData.surface[i] = find_surface(wheel.get_collider(), wheel.get_collision_point(), providers, default_surface)


## Returns the surface at [param point] on [param collider].
func find_surface(collider: Object, point: Vector3, providers: Array, default_surface: ShiftSurface) -> ShiftSurface:
	if collider and collider.has_meta(SURFACE_META):
		var surface = collider.get_meta(SURFACE_META)
		if surface is ShiftSurface:
			return surface

	for provider in providers:
		if provider.has_method("get_surface"):
			var surface = provider.get_surface(point, collider)
			if surface:
				return surface

	return default_surface
