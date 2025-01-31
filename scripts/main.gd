extends Node3D

@onready var camera = $ControlCamera3D
var current_hover: Area3D = null

var _save_path_fullscreen_mode = "user://fullscreen_mode.save"
var _toggle_fullscreen_action: StringName = "toggle_fullscreen"
var _exit_app_action: StringName = "exit"

func _ready():
	_initialize_input_system()
	_apply_saved_display_settings()

func _process(delta):
	_process_input_actions()
	_process_cursor_hover()

func _input(event):
	_handle_mouse_click(event)

#region Input System
func _initialize_input_system():
	_setup_action(_toggle_fullscreen_action, Key.KEY_ENTER, true)
	_setup_action(_exit_app_action, Key.KEY_ESCAPE)
	_load_fullscreen_mode()

func _setup_action(action: StringName, key: Key, alt: bool = false):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = key
		event.alt_pressed = alt
		InputMap.action_add_event(action, event)

func _process_input_actions():
	if Input.is_action_just_pressed(_toggle_fullscreen_action):
		_toggle_fullscreen_mode()
	
	if Input.is_action_just_pressed(_exit_app_action):
		get_tree().quit()
#endregion

#region Display Management
func _toggle_fullscreen_mode():
	var new_mode = DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN
	_update_fullscreen_mode(new_mode)

func _update_fullscreen_mode(mode: DisplayServer.WindowMode):
	DisplayServer.window_set_mode(mode)
	_save_fullscreen_mode(mode)

func _save_fullscreen_mode(mode: DisplayServer.WindowMode):
	FileAccess.open(_save_path_fullscreen_mode, FileAccess.WRITE).store_var(mode)

func _load_fullscreen_mode():
	if FileAccess.file_exists(_save_path_fullscreen_mode):
		DisplayServer.window_set_mode(FileAccess.open(_save_path_fullscreen_mode, FileAccess.READ).get_var())

func _apply_saved_display_settings():
	_load_fullscreen_mode()
#endregion

#region Cursor Interaction
func _process_cursor_hover():
	var ray_params = _create_ray_query()
	var result = get_world_3d().direct_space_state.intersect_ray(ray_params)
	_handle_collision_result(result.get("collider") if result else null)

func _create_ray_query() -> PhysicsRayQueryParameters3D:
	var params = PhysicsRayQueryParameters3D.new()
	var mouse_pos = get_viewport().get_mouse_position()
	params.from = camera.project_ray_origin(mouse_pos)
	params.to = params.from + camera.project_ray_normal(mouse_pos) * 1000
	params.collide_with_areas = true
	return params

func _handle_collision_result(collider):
	if collider is Area3D:
		_update_hovered_target(collider)
	else:
		_clear_hovered_target()

func _update_hovered_target(new_target: Area3D):
	if new_target != current_hover:
		_clear_hovered_target()
		current_hover = new_target
		current_hover.emit_signal("mouse_entered")

func _clear_hovered_target():
	if current_hover:
		current_hover.emit_signal("mouse_exited")
		current_hover = null

func _handle_mouse_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_hover:
			current_hover.emit_signal("mouse_clicked")
#endregion
