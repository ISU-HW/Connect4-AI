extends Node

var raycast: RayCast3D

func _ready():
	raycast = RayCast3D.new()
	add_child(raycast)
	raycast.enabled = true
	raycast.set_collision_mask_value(2, true)

func _input(event):
	if event is InputEventMouseMotion:
		_update_raycast(event.position)
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_raycast(event.position)
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider.get_parent() is ClickBox:
				var camera = get_viewport().get_camera_3d()
				var collision_point = raycast.get_collision_point()
				var collision_normal = raycast.get_collision_normal()
				var shape_idx = raycast.get_collision_shape()
				collider._on_input_event(camera, event, collision_point, collision_normal, shape_idx)

func _update_raycast(mouse_pos: Vector2):
	var camera = get_viewport().get_camera_3d()
	if !camera:
		return
	
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	raycast.global_position = from
	raycast.look_at(to, Vector3.UP)
	raycast.target_position = Vector3(0, 0, 1000)
	raycast.force_raycast_update()
