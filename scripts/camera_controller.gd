@tool
class_name CameraOrbitController
extends Node

#region Exports
@export_group("Camera Reference")
@export var camera: Camera3D

@export_group("Orbit Settings")
@export var pivot_offset: Vector3 = Vector3(0, 0, 5.0)
@export var rotation_speed: float = 1.0
@export var zoom_speed: float = 1.0
@export var zoom_limits: Vector2 = Vector2(1, 10)

@export_group("Rotation Limits")
@export var lock_rotation_x: bool = false
@export var lock_rotation_y: bool = false
@export_range(-90, 90, 0.1) var min_x_angle: float = -90.0
@export_range(-90, 90, 0.1) var max_x_angle: float = 90.0
@export_range(0, 360, 1.0) var y_angle_limit: float = 360.0
#endregion

#region Internal State
var _enabled: bool = true
var _current_pivot: Vector3
var _current_rotation: Vector2
var _target_zoom: float
#endregion

func _ready() -> void:
	if camera:
		_current_pivot = camera.global_position + camera.global_transform.basis.z * pivot_offset.z
		_target_zoom = pivot_offset.z

func set_enabled(value: bool) -> void:
	_enabled = value
	set_process_unhandled_input(value)

func update_camera_transform() -> void:
	if !camera:
		return
	
	var basis = Basis() \
		.rotated(Vector3.RIGHT, _current_rotation.x) \
		.rotated(Vector3.UP, _current_rotation.y)
	
	var rotated_offset = basis.z * _target_zoom
	camera.global_position = _current_pivot - rotated_offset
	camera.look_at(_current_pivot)

func _unhandled_input(event: InputEvent) -> void:
	if !_enabled || !camera.current:
		return
	
	if event is InputEventMouseMotion:
		_handle_rotation(event)
	
	if event is InputEventMouseButton:
		_handle_zoom(event)

func _handle_rotation(event: InputEventMouseMotion) -> void:
	var relative = event.relative * 0.002 * rotation_speed
	
	if !lock_rotation_y:
		_current_rotation.y = wrapf(
			_current_rotation.y - relative.x,
			-deg_to_rad(y_angle_limit),
			deg_to_rad(y_angle_limit)
		)
	
	if !lock_rotation_x:
		_current_rotation.x = clamp(
			_current_rotation.x + relative.y,
			deg_to_rad(min_x_angle),
			deg_to_rad(max_x_angle)
		)
	
	update_camera_transform()

func _handle_zoom(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clamp(_target_zoom - zoom_speed, zoom_limits.x, zoom_limits.y)
		MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clamp(_target_zoom + zoom_speed, zoom_limits.x, zoom_limits.y)
	
	update_camera_transform()
