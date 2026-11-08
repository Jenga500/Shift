## Tells the Shift cars which [ShiftSurface] a Terrain3D terrain has at a point,
## from the terrain's painted textures.
##
## Add this node anywhere in the scene (for example as a child of the Terrain3D
## node), set [member terrain] and fill [member surfaces]: the entry at index N
## is the surface for the texture with ID N in Terrain3D's asset dock. Empty
## entries and IDs past the end of the list fall back to the car's default
## surface.
##
## Where Terrain3D blends two textures, the one that shows more (base or
## overlay) is used. Points that are outside the terrain's regions, in a hole,
## or more than [member height_tolerance] above the terrain (a road mesh or a
## bridge over the terrain) are left to the other lookups.
##
## Uses [code]terrain.data.get_texture_id()[/code] and
## [code]get_surface_height()[/code] (Terrain3D 1.0 and newer). Terrain3D is not
## needed for the rest of the addon; this script only talks to it when used.
class_name ShiftTerrain3DSurfaces
extends Node

## The Terrain3D node.
@export var terrain: Node3D
## Surface per Terrain3D texture ID (index 0 = texture 0 in the asset dock).
@export var surfaces: Array[ShiftSurface] = []
## How far above the terrain surface (in meters) a wheel contact may be to still
## count as being on the terrain.
@export var height_tolerance := 0.3


func _enter_tree() -> void:
	add_to_group(&"shift_surface_providers")


## Returns the surface at [param point], or null if the point is not on the
## terrain or the texture has no surface assigned. [param collider] is not
## needed for Terrain3D and is ignored.
func get_surface(point: Vector3, collider: Object) -> ShiftSurface:
	if terrain == null or surfaces.is_empty():
		return null
	var data = terrain.get("data")
	if data == null:
		return null

	var texture: Vector3 = data.get_texture_id(point)
	if is_nan(texture.x):
		return null # outside the regions or a hole

	var ground: float = data.get_surface_height(point) if data.has_method("get_surface_height") else data.get_height(point)
	if is_nan(ground) or point.y - ground > height_tolerance:
		return null # on something above the terrain

	var id := int(texture.y) if texture.z > 0.5 else int(texture.x)
	if id < 0 or id >= surfaces.size():
		return null
	return surfaces[id]
