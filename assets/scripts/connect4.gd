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

const rows: int = 6
const cols: int = 7
var spawnconfig_player1 = load("res://assets/tres/spawnconfig_PLAYER1.tres")
var spawnconfig_player2 = load("res://assets/tres/spawnconfig_PLAYER2.tres")
var drop_chip_cooldown = 0.3

var users: Dictionary = {"PLAYER": PlayerState.PLAYER1, "AI": PlayerState.PLAYER2}
var game_board: Array = []
var current_player: int = PlayerState.PLAYER1
var player_winner: int = PlayerState.EMPTY
var win_chips: Array
var last_move: Vector2i
var wins: int = 0
var losses: int = 0
var draws: int = 0

#region Game Initializing
func _ready():
	_load_data()
	_initialize_game()

func _initialize_game():
	_setup_game_state()
	_create_board()
	_setup_timer()

func _setup_game_state():
	current_player = PlayerState.PLAYER1
	player_winner = 0
	win_chips = []
	last_move = Vector2i()

func _setup_timer():
	drop_chip_timer.autostart = true
	drop_chip_timer.one_shot = true
	drop_chip_timer.wait_time = drop_chip_cooldown
	drop_chip_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(drop_chip_timer)

func _create_board():
	game_board = []
	for col in range(cols):
		game_board.append([])
		for row in range(rows):
			game_board[col].append(PlayerState.EMPTY)
#endregion

#region Public Methods
func is_game_started():
	if not is_board_empty() and not is_board_full() and player_winner == PlayerState.EMPTY:
		return true
	return false
	
func is_game_ended():
	if player_winner != PlayerState.EMPTY or is_board_full():
		return true
	return false

func restart_game():
	_setup_game_state()
	_create_board()
	get_tree().reload_current_scene()

func set_user_player(player):
	match player:
		PlayerState.PLAYER1:
			users["PLAYER"] = PlayerState.PLAYER1
			users["AI"] = PlayerState.PLAYER2
		PlayerState.PLAYER2:
			users["PLAYER"] = PlayerState.PLAYER2
			users["AI"] = PlayerState.PLAYER1
			turn_changed.emit()
			
func win_matches(board: Array, row: int, col: int, player: PlayerState) -> Array:
	const directions = [
		Vector2i(1, 0),    # вертикаль
		Vector2i(0, 1),    # горизонталь
		Vector2i(1, 1),    # диагональ по нисходящей
		Vector2i(1, -1)    # диагональ по восходящей
	]
	
	for direction in directions:
		var matches = _win_matches_in_direction(board, col, row, direction, player)
		if matches.size() >= 4:
			return matches
	return []  # Если ни в одном направлении не найдено 4-х подряд

func drop_chip(user: String, col: int):
	if is_board_empty():
		start.emit()
		
	if not drop_chip_timer.time_left == 0 or current_player != PlayerState.EMPTY and users[user] != current_player or not _is_valid_move(col):
		not_valid_move.emit()
		return false

	for row in range(rows - 1, -1, -1):
		if game_board[col][row] == PlayerState.EMPTY:
			drop_chip_timer.start()
			game_board[col][row] = current_player

			last_move = Vector2i(row, col)
			chip_dropped.emit(last_move, current_player)

			win_chips = win_matches(game_board, row, col, current_player)
			print(win_chips)
			if win_chips:
				player_winner = current_player
				match player_winner:
					users.PLAYER:
						wins += 1
					users.AI:
						losses += 1
				win.emit()
				print("Player ", current_player, " wins!")
			elif is_board_full():
				current_player = PlayerState.EMPTY
				player_winner = PlayerState.EMPTY
				draws += 1
				draw.emit()
				print("A draw")

			_switch_turn()
			_save_data()
			return true
	return false

func get_all_valid_moves() -> Array:
	var valid_moves = []
	for col in range(cols):
		if _is_valid_move(col):
			valid_moves.append(col)
	return valid_moves
	
func is_board_full() -> bool:
	for col in game_board:
		if PlayerState.EMPTY in col:
			return false
	return true

func is_board_empty() -> bool:
	for col in game_board:
		if PlayerState.PLAYER1 in col or PlayerState.PLAYER2 in col:
			return false
	return true
#endregion

#region Private Methods
func _is_valid_move(col):
	return player_winner == PlayerState.EMPTY and game_board[col][0] == PlayerState.EMPTY and col >= 0 and col < connect4.cols

func _switch_turn():
	match current_player:
		PlayerState.EMPTY:
			current_player = PlayerState.EMPTY
		PlayerState.PLAYER1:
			current_player = PlayerState.PLAYER2
		PlayerState.PLAYER2:
			current_player = PlayerState.PLAYER1
	turn_changed.emit()

# Вспомогательная функция для поиска совпадений в заданном направлении с учётом токена игрока
func _win_matches_in_direction(board: Array, col: int, row: int, direction: Vector2i, player: PlayerState) -> Array:
	var forward = _get_matches_in_direction(board, col, row, direction.y, direction.x, player)
	var backward = _get_matches_in_direction(board, col, row, -direction.y, -direction.x, player)
	backward.reverse()
	var all_matches = backward + [Vector2i(row, col)] + forward
	return all_matches

# Функция, собирающая подряд идущие ячейки с указанным токеном вдоль заданного направления
func _get_matches_in_direction(board: Array, start_col: int, start_row: int, step_col: int, step_row: int, player: PlayerState) -> Array:
	var current_row = start_row + step_row
	var current_col = start_col + step_col
	var matches = []
	while current_row >= 0 and current_row < connect4.rows and current_col >= 0 and current_col < connect4.cols:
		if board[current_col][current_row] != player:
			break
		matches.append(Vector2i(current_row, current_col))
		current_row += step_row
		current_col += step_col
	return matches

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
#endregion
