extends Node3D

var _save_path_fullscreen_mode = "user://fullscreen_mode.save"
var _toggle_fullscreen_action: StringName = "toggle_fullscreen"
var _exit_app_action: StringName = "exit"
var _restart_game_action:StringName = "reload_game"

func _ready():
	_initialize_input_system()
	_apply_saved_display_settings()

func _process(_delta):
	_process_input_actions()

#region Input System
func _initialize_input_system():
	_setup_action(_toggle_fullscreen_action, Key.KEY_ENTER, true)
	_setup_action(_exit_app_action, Key.KEY_ESCAPE)
	_setup_action(_restart_game_action, Key.KEY_R)
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
		
	if Input.is_action_just_pressed(_restart_game_action):
		connect4._initialize(1)
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
