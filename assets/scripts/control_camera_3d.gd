@tool
@icon("res://addons/control_camera3d/control_camera3d.svg")
extends Camera3D

## Global position of pivot point
@export var pivot_pos: Vector3 = Vector3.ZERO:
	set(value):
		pivot_pos = value
		_place_pivot()

@export_group("Camera Control")
## Mouse button for orbital movement
@export var enable: bool = true
@export_enum("LEFT_BUTTON", "MIDDLE_BUTTON", "RIGHT_BUTTON") var action_mouse_button: String = "MIDDLE_BUTTON"
@export_range(0.5, 10, 0.1) var rotation_speed: float = 1.0
@export_range(0, 10, 0.1) var translation_speed: float = 1.0
@export_range(0, 10, 0.1) var zoom_speed: float = 1.0
@export var zoom_in: float = 1:
	set(value):
		if value > 0: zoom_in = value
@export var zoom_out: float = 10:
	set(value):
		if value > zoom_in: zoom_out = value

@export_group("Rotation Limits")
@export var lock_rotation_x: bool = false
@export var lock_rotation_y: bool = false
@export_range(-90, 90, 0.1) var min_x_angle: float = -90.0:
	set(value):
		var current_max = max_x_angle if max_x_angle != TYPE_NIL else 90.0
		min_x_angle = clamp(value, -90.0, current_max)

@export_range(-90, 90, 0.1) var max_x_angle: float = 90.0:
	set(value):
		var current_min = min_x_angle if min_x_angle != TYPE_NIL else -90.0
		max_x_angle = clamp(value, current_min, 90.0)
@export_range(0, 360, 1.0) var y_angle_limit: float = 360.0

@export_group("Edge Control")
@export_range(5, 200) var edge_threshold: int = 10

@export_group("Home Action")
@export_enum("SPACE", "H") var home_action_button: String = "SPACE"
@export var home_return_duration: float = 0.3
@export var home_ease_curve: Curve

var _state: int = State.IDLE
var _cam_from_pivot_dist: float
var _pivot_transform: Transform3D
var _pole_mesh := ImmediateMesh.new()
var _pole_mesh_instance := MeshInstance3D.new()
var _pole_mat := StandardMaterial3D.new()
var _ignore_next_mouse_motion: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _actual_x_angle: float = 0.0
var _actual_y_angle: float = 0.0
var _target_zoom: float = 0.0
var _reset_tween: Tween
@onready var _home_transform: Transform3D = global_transform
@onready var _home_rotation: Vector3 = _pivot_transform.basis.get_euler()

enum State {
	IDLE,
	ROTATED,
	TRANSLATED,
	LOOKAT,
	LOCKED,
}

const _MOUSE_SENSITIVITY = 0.002
const _WHEEL_SENSITIVITY = 0.5
const _ANGLE_GAP = PI/128

func _ready() -> void:
	connect4.win.connect(_on_end)
	connect4.draw.connect(_on_end)
	
	_place_pivot()
	var initial_angles = _pivot_transform.basis.get_euler()
	_actual_x_angle = initial_angles.x
	_actual_y_angle = initial_angles.y
	_target_zoom = _cam_from_pivot_dist

	_pole_mat.vertex_color_use_as_albedo = true
	_pole_mesh_instance.mesh = _pole_mesh
	_pole_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pole_mesh_instance)

func _place_pivot():
	if abs(_cam_from_pivot_dist - _target_zoom) < 0.01:
		if is_inside_tree() and global_position != pivot_pos:
			_pivot_transform = Transform3D(Basis(), pivot_pos)
			_pivot_transform = _pivot_transform.looking_at(global_position)
			_cam_from_pivot_dist = global_position.distance_to(pivot_pos)
			_target_zoom = _cam_from_pivot_dist
			var new_cam_pos: Vector3 = _pivot_transform.basis.z * -_cam_from_pivot_dist + pivot_pos
			look_at_from_position(new_cam_pos, pivot_pos)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_place_pivot()
		var global_tr_inv = global_transform.inverse()
		var pivot_global_pos = (global_tr_inv * _pivot_transform).origin
		_pole_mesh.clear_surfaces()
		_pole_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _pole_mat)
		_pole_mesh.surface_set_color(Color.WEB_PURPLE)
		_pole_mesh.surface_add_vertex(Vector3.ZERO)
		_pole_mesh.surface_add_vertex(pivot_global_pos)
		_pole_mesh.surface_end()

	# Smooth zoom
	if abs(_cam_from_pivot_dist - _target_zoom) > 0.01:
		_cam_from_pivot_dist = lerp(_cam_from_pivot_dist, _target_zoom, delta * 5)
		var new_cam_pos: Vector3 = _pivot_transform.basis.z * -_cam_from_pivot_dist + pivot_pos
		global_position = new_cam_pos

func _unhandled_input(event: InputEvent) -> void:
	if not current or not enable: return

	if event is InputEventKey and event.pressed:
		var is_home_key = (home_action_button == "SPACE" and event.keycode == KEY_SPACE) or \
						  (home_action_button == "H" and event.keycode == KEY_H)
		if is_home_key:
			home_return()
			get_viewport().set_input_as_handled()
			return

	if _state == State.LOCKED:
		return

	if event is InputEventMouseButton:
		var should_rotate = false
		match action_mouse_button:
			"MIDDLE_BUTTON": should_rotate = event.button_index == MOUSE_BUTTON_MIDDLE
			"LEFT_BUTTON": should_rotate = event.button_index == MOUSE_BUTTON_LEFT
			"RIGHT_BUTTON": should_rotate = event.button_index == MOUSE_BUTTON_RIGHT

		if should_rotate:
			_state = State.ROTATED if event.pressed else State.IDLE
			if event.pressed:
				var initial_angles = _pivot_transform.basis.get_euler()
				_actual_x_angle = initial_angles.x
				_actual_y_angle = initial_angles.y

	match _state:
		State.IDLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			pivot_pos = _pivot_transform.origin
		State.ROTATED, State.TRANSLATED, State.LOOKAT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

	if event is InputEventMouseMotion and _state == State.ROTATED:
		if _ignore_next_mouse_motion:
			_ignore_next_mouse_motion = false
			return

		_handle_camera_rotation(event)
		_handle_cursor_warp(event)
		_last_mouse_pos = event.position

	if event is InputEventMouseMotion and _state == State.TRANSLATED:
		_pivot_transform = _pivot_transform.translated_local(
			Vector3(event.relative.x * _MOUSE_SENSITIVITY * translation_speed,
					-event.relative.y * _MOUSE_SENSITIVITY * translation_speed,
					0))
		global_transform = global_transform.translated_local(
			Vector3(-event.relative.x * _MOUSE_SENSITIVITY * translation_speed,
					event.relative.y * _MOUSE_SENSITIVITY * translation_speed,
					0))

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clamp(_target_zoom - _WHEEL_SENSITIVITY * zoom_speed, zoom_in, zoom_out)

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clamp(_target_zoom + _WHEEL_SENSITIVITY * zoom_speed, zoom_in, zoom_out)

func _handle_camera_rotation(event: InputEventMouseMotion) -> void:
	if _state == State.LOCKED: return

	var relative_motion = event.relative

	# Обработка вращения по Y
	if not lock_rotation_y:
		_actual_y_angle -= relative_motion.x * _MOUSE_SENSITIVITY * rotation_speed
		if y_angle_limit < 360.0:
			_actual_y_angle = clamp(
				_actual_y_angle,
				-deg_to_rad(y_angle_limit),
				deg_to_rad(y_angle_limit)
			)
		else:
			_actual_y_angle = wrapf(_actual_y_angle, -TAU, TAU)
	else:
		_actual_y_angle = _pivot_transform.basis.get_euler().y

	# Обработка вращения по X
	if not lock_rotation_x:
		var delta_angle = relative_motion.y * _MOUSE_SENSITIVITY * rotation_speed

		# Преобразование градусов в радианы и определение границ
		var rad_min = deg_to_rad(min_x_angle)
		var rad_max = deg_to_rad(max_x_angle)
		var lower_bound = min(rad_min, rad_max)
		var upper_bound = max(rad_min, rad_max)

		# Применение ограничений с плавной коррекцией
		var new_angle = _actual_x_angle + delta_angle
		if new_angle < lower_bound:
			new_angle = lerp(_actual_x_angle, lower_bound, 0.5)
		elif new_angle > upper_bound:
			new_angle = lerp(_actual_x_angle, upper_bound, 0.5)

		_actual_x_angle = clamp(new_angle, lower_bound, upper_bound)
	else:
		_actual_x_angle = _pivot_transform.basis.get_euler().x

	# Обновление позиции камеры
	_pivot_transform.basis = Basis.from_euler(Vector3(_actual_x_angle, _actual_y_angle, 0))
	var new_cam_pos: Vector3 = _pivot_transform.basis.z * -_cam_from_pivot_dist + pivot_pos
	look_at_from_position(new_cam_pos, pivot_pos)

func _handle_cursor_warp(event: InputEventMouseMotion) -> void:
	var viewport = get_viewport()
	var viewport_size = viewport.size
	var mouse_pos = event.position

	var new_mouse_pos = mouse_pos
	var warp = false

	if mouse_pos.x <= edge_threshold:
		new_mouse_pos.x = viewport_size.x - edge_threshold
		warp = true
	elif mouse_pos.x >= viewport_size.x - edge_threshold:
		new_mouse_pos.x = edge_threshold
		warp = true

	if mouse_pos.y <= edge_threshold:
		new_mouse_pos.y = viewport_size.y - edge_threshold
		warp = true
	elif mouse_pos.y >= viewport_size.y - edge_threshold:
		new_mouse_pos.y = edge_threshold
		warp = true

	if warp:
		Input.warp_mouse(new_mouse_pos)
		_ignore_next_mouse_motion = true
		event.relative = event.relative.lerp(Vector2.ZERO, 0.7)

func home_return() -> void:
	_state = State.LOCKED
	var start_transform = global_transform
	var start_rotation = _pivot_transform.basis.get_euler()

	if _reset_tween:
		_reset_tween.kill()

	_reset_tween = create_tween()
	_reset_tween.tween_method(
		_apply_home_animation.bind(start_transform, start_rotation),
		0.0,
		1.0,
		home_return_duration
	)
	_reset_tween.tween_callback(func():
		_state = State.IDLE
	)

func _apply_home_animation(progress: float, start_tr: Transform3D, start_rot: Vector3) -> void:
	var curve_value = home_ease_curve.sample(progress)
	global_transform = start_tr.interpolate_with(_home_transform, curve_value)
	_pivot_transform.basis = Basis.from_euler(start_rot.lerp(_home_rotation, curve_value))
	_cam_from_pivot_dist = global_position.distance_to(pivot_pos)
	_target_zoom = _cam_from_pivot_dist

func _on_end():
	self.enable = false
	home_return()
