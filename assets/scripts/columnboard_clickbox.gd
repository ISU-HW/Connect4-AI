class_name ClickBox
extends Area3D

signal clicked(event: InputEvent)
signal mouse_entered_area()
signal mouse_exited_area()

@export var track_mouse_hover: bool = true
@export var column: int = 0

func _ready():
	input_event.connect(_on_input_event)
	connect4.chip_dropped.connect(_on_chip_dropped)
	input_ray_pickable = true
	
	connect4.win.connect(_on_end)
	connect4.draw.connect(_on_end)
	if track_mouse_hover:
		_connect_hover_signals()
	else:
		_disconnect_hover_signals()

func _connect_hover_signals():
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

func _disconnect_hover_signals():
	if mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.disconnect(_on_mouse_entered)
	if mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.disconnect(_on_mouse_exited)

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			connect4.drop_chip("PLAYER", column)
			clicked.emit()

func _on_mouse_entered():
	mouse_entered_area.emit()

func _on_mouse_exited():
	mouse_exited_area.emit()

func _on_chip_dropped(board_position, current_player):
	if board_position.y == self.column:
		$Spawnpoint.spawn_by_index_variants(current_player - 1)

func _on_end():
	mouse_exited_area.emit()
	_disconnect_hover_signals()
