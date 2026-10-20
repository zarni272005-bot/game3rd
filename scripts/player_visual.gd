class_name ArenaPlayerVisual
extends Node3D

var peer_id := 1
var target_position := Vector3.ZERO


func _ready() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.8

	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position.y = 0.9

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(float((peer_id * 37) % 100) / 100.0, 0.68, 0.92)
	body.material_override = material
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.3
	head_mesh.height = 0.6
	head.mesh = head_mesh
	head.position.y = 1.9
	head.material_override = material
	add_child(head)


func set_target(world_position: Vector3, delta: float) -> void:
	target_position = world_position
	position = position.lerp(target_position, min(1.0, delta * 12.0))
