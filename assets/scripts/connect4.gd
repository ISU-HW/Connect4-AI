class_name Connect4
extends Node

signal chip_dropped
signal turn_changed
signal not_valid_move
signal start
signal win
signal draw

var drop_chip_timer: Timer = Timer.new()
enum PlayerState { EMPTY = 0, PLAYER1 = 1, PLAYER2 = 2 }

@export var spawnconfig_player1 = load("res://assets/tres/spawnconfig_PLAYER1.tres")
@export var spawnconfig_player2 = load("res://assets/tres/spawnconfig_PLAYER2.tres")

const rows: int = 6
const cols: int = 7

var drop_chip_cooldown = 0.3
var users: Dictionary = {"PLAYER": PlayerState.PLAYER1, "AI": PlayerState.PLAYER2}
var board: Array = []
var current_player: int = PlayerState.PLAYER1
var win_chips: Array
var last_move: Vector2i
var player_winner: int = 0
var wins: int = 0
var losses: int = 0
var draws: int = 0

func _ready():
	_load_data()
	#choose player
	#if user_choose != PlayerState.PLAYER1:
		#users["PLAYER"] = PlayerState.PLAYER2
		#users["AI"] = PlayerState.PLAYER1
	initialize(0)
	_connect_signals()

func initialize(is_restart: bool):
	if is_restart:
		print("Restart!")
		get_tree().reload_current_scene()
		return
		
	start.emit()
	drop_chip_timer.one_shot = true
	drop_chip_timer.wait_time = drop_chip_cooldown
	drop_chip_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(drop_chip_timer)
	
	board = []
	for row in range(rows):
		board.append([])
		for col in range(cols):
			board[row].append(PlayerState.EMPTY)
			

func _connect_signals():
	var restart_button: Button = $"/root/Main/win_menu/CenterContainer/VBoxContainer/Button"
	var main = $"/root/Main"
	if restart_button:
		restart_button.game_restart.connect(initialize.bind(1))
	if main:
		main.game_restart.connect(initialize.bind(1))

func _is_valid_move(col):
	#and current_player is not user_player
	return drop_chip_timer.time_left == 0 and player_winner == 0 and board[0][col] == PlayerState.EMPTY

func drop_chip(user, col):
	if not _is_valid_move(col):
		not_valid_move.emit()
		return false
		
	#check user for right player turn if not set setting to ignore all users except "I" for debug
	#if users[user] == current_player:

	for row in range(rows - 1, -1, -1):
		if board[row][col] == PlayerState.EMPTY:
			drop_chip_timer.start()
			board[row][col] = current_player
			
			last_move = Vector2i(row, col)
			chip_dropped.emit(last_move, current_player)
			
			win_chips = _win_matches(row, col)
			print(win_chips)
			if win_chips:
				player_winner = current_player
				win.emit()
				print("Player ", current_player, " wins!")
			elif _is_board_full():
				current_player = PlayerState.EMPTY
				player_winner = PlayerState.EMPTY
				draw.emit()
				print("It's a draw!")
			_switch_turn()
			_save_data()
			return true
	return false

func _switch_turn():
	match current_player:
		PlayerState.PLAYER1:
			current_player = PlayerState.PLAYER2
		PlayerState.PLAYER2:
			current_player = PlayerState.PLAYER1
	turn_changed.emit()

func _win_matches(row, col):
	const d_vertical = Vector2i(1, 0)
	const d_horizontal = Vector2i(0, 1)
	const d_diagonal_down = Vector2i(1, 1)
	const d_diagonal_up = Vector2i(1, -1)
	
	var directions = [d_vertical, d_horizontal, d_diagonal_down, d_diagonal_up]
	for direction in directions:
		var matches = _win_matches_in_direction(row, col, direction)
		if matches:
			return matches
	return []

func _win_matches_in_direction(row, col, direction: Vector2i):
	var forward = _get_matches_in_direction(row, col, direction.x, direction.y)
	var backward = _get_matches_in_direction(row, col, -direction.x, -direction.y)
	backward.reverse()
	var all_matches = backward + [Vector2i(row, col)] + forward
	return all_matches if all_matches.size() >= 4 else []

func _get_matches_in_direction(start_row, start_col, step_row, step_col):
	var current_row = start_row + step_row
	var current_col = start_col + step_col
	var matches = []
	while current_row >= 0 and current_row < rows and current_col >= 0 and current_col < cols:
		if board[current_row][current_col] != current_player:
			break
		matches.append(Vector2i(current_row, current_col))
		current_row += step_row
		current_col += step_col
	return matches
	
func _is_board_full() -> bool:
	for row in board:
		if PlayerState.EMPTY in row:
			return false
	return true
	
func _save_data():
	var config = ConfigFile.new()
	config.set_value("Connect4", "wins", wins)
	config.set_value("Connect4", "losses", losses)
	config.set_value("Connect4", "draws", draws)
	var err = config.save("user://save.cfg")
	if err != OK:
		print("Failed to save data: ", err)

func _load_data():
	var config = ConfigFile.new()
	var err = config.load("user://save.cfg")
	if err == OK:
		wins = config.get_value("Connect4", "wins", 0)
		losses = config.get_value("Connect4", "losses", 1)
		draws = config.get_value("Connect4", "draws", 2)
	else:
		print("Failed to load data: ", err)


func get_board():
	return board

# Получение текущего хода
func get_current_player():
	return current_player
