extends Button

@export var player: connect4.PlayerState
@export var unpressed_blend_color: Color = Color(0.7, 0.7, 0.7, 0.6)

var PLAYER_COLORS = {
	connect4.PlayerState.PLAYER1: connect4.spawnconfig_player1.model_color,
	connect4.PlayerState.PLAYER2: connect4.spawnconfig_player2.model_color
}

var stylebox_normal = StyleBoxFlat.new()
var stylebox_hover = StyleBoxFlat.new()
var stylebox_pressed = StyleBoxFlat.new()

func _ready() -> void:
	pressed.connect(_on_press)
	
	self.add_to_group("buttons")
	#if player == connect4.PlayerState.PLAYER1:
		#button_pressed = true
	
	stylebox_normal.bg_color = PLAYER_COLORS[player]
	stylebox_hover.bg_color = PLAYER_COLORS[player].lightened(0.2)
	stylebox_pressed.bg_color = PLAYER_COLORS[player]
	add_theme_stylebox_override("normal", stylebox_normal)
	add_theme_stylebox_override("hover", stylebox_hover)
	add_theme_stylebox_override("pressed", stylebox_pressed)

func _on_press():
	#if not self.button_pressed:
		#self.button_pressed = true
		#return
		
	#_unpress_button_group()
	connect4.set_user_player(player)
	connect4.start.emit()
	connect4.is_game_started = true

func _unpress_button_group():
	var group = self.button_group.get_buttons()
	var current_pressed_button = self.button_group.get_pressed_button()
	if current_pressed_button:
		group.pop_at(group.find(current_pressed_button))
	for button in group:
		button.button_pressed = false
