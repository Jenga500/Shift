extends Node3D




var color: Color = Color.WHITE:
	set(value):
		color = value
		if material:
			material.albedo_color = color
var force: Vector3
var Position_Offset: Vector3
var DEBUG: bool
var Display_Force_Magntiude: bool

var cyl_mesh: CylinderMesh
var material: StandardMaterial3D

func _ready() -> void:
	cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = 0.01
	cyl_mesh.bottom_radius = 0.05
	cyl_mesh.height = 1.0

	material = StandardMaterial3D.new()
	material.albedo_color = color
	cyl_mesh.material = material

	$Center/Arrow.mesh = cyl_mesh

func _process(_delta: float) -> void:

	visible = true
	update_force_arrow()
	update_force_label()

func update_force_arrow():
	var magnitude = force.length()

	if magnitude < 0.0001:
		$Center/Arrow.visible = false
		return

	$Center/Arrow.visible = true
	var direction = force / magnitude
	var length = magnitude * 0.001

	cyl_mesh.height = length

	# the force is in world space and the wheel mesh this hangs on spins, so the
	# arrow is placed in world space, with the side offset taken from the wheel
	# ray (the mesh's parent), which does not roll
	var ray: Node3D = get_parent_node_3d().get_parent_node_3d()
	var offset: Vector3 = ray.global_basis.orthonormalized() * Position_Offset if ray else Position_Offset
	$Center/Arrow.global_basis = Basis(Quaternion(Vector3.UP, direction))
	$Center/Arrow.global_position = $Center.global_position + direction * (length / 2.0) + offset
	
func update_force_label():
	if Display_Force_Magntiude == true:
		var magnitude = force.length()
		$Center/Force_Magnitude.text = "%.1f" % magnitude
