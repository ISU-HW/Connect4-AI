class_name Connect4
extends Node

signal chip_dropped
signal turn_changed
signal not_valid_move
signal start
signal win
signal draw

var drop_chip_timer: Timer = Timer.new()
var player1_timer: Timer = Timer.new()
var player2_timer: Timer = Timer.new()
enum PlayerState { EMPTY = 0, PLAYER1 = 1, PLAYER2 = 2 }

const rows: int = 6
const cols: int = 7
var spawnconfig_player1 = load("res://assets/tres/spawnconfig_PLAYER1.tres")
var spawnconfig_player2 = load("res://assets/tres/spawnconfig_PLAYER2.tres")
var drop_chip_cooldown = 0.3
var player_time = 300.0

var users: Dictionary = {"PLAYER": PlayerState.PLAYER1, "AI": PlayerState.PLAYER2}
var game_board: Array = []
var move_history: Array = []
var player1_time_remaining: float
var player2_time_remaining: float
var current_player: int = PlayerState.PLAYER1
var player_winner: int = PlayerState.EMPTY
var win_chips: Array
var last_move: Vector2i
var is_game_started: bool = false

#region Game Initializing
func _ready():
	_initialize_game()

func _initialize_game():
	_setup_game_state()
	_create_board()
	_setup_timers()
	start.connect(_on_start)
	
func _setup_game_state():
	move_history = []
	is_game_started = false
	current_player = PlayerState.PLAYER1
	player_winner = 0
	win_chips = []
	last_move = Vector2i()

func _setup_timers():
	drop_chip_timer.autostart = true
	drop_chip_timer.one_shot = true
	drop_chip_timer.wait_time = drop_chip_cooldown
	add_child(drop_chip_timer)
	
	player1_timer.one_shot = true
	player2_timer.one_shot = true
	player1_timer.timeout.connect(_on_player1_timeout)
	player2_timer.timeout.connect(_on_player2_timeout)
	add_child(player1_timer)
	add_child(player2_timer)

func _create_board():
	game_board = []
	for col in range(cols):
		game_board.append([])
		for row in range(rows):
			game_board[col].append(PlayerState.EMPTY)
#endregion

#region Handlers
func _on_start():
	var player_timer_ui = $/root/Main/start_menu/CenterContainer/Container/VBoxContainer/time/player_timer
	if player_timer_ui != null:
		player_timer_ui.apply()
		player_time = int(player_timer_ui.get_line_edit().text)
	player1_timer.wait_time = player_time
	player2_timer.wait_time = player_time
	player1_time_remaining = player_time
	player2_time_remaining = player_time
#endregion

#region Public Methods
func is_game_ended():
	if player_winner != PlayerState.EMPTY or is_board_full():
		return true
	return false

func restart_game():
	_setup_game_state()
	_create_board()
	player1_timer.stop()
	player2_timer.stop()
	drop_chip_timer.stop()
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
	return []

func drop_chip(user: String, col: int):
	if not is_game_started:
		return
	
	if not drop_chip_timer.time_left == 0 or current_player != PlayerState.EMPTY and users[user] != current_player or not _is_valid_move(col):
		not_valid_move.emit()
		return 

	for row in range(rows - 1, -1, -1):
		if game_board[col][row] == PlayerState.EMPTY:
			drop_chip_timer.start()
			game_board[col][row] = current_player

			last_move = Vector2i(row, col)
			chip_dropped.emit(last_move, current_player)

			# Запоминаем ход в шахматной нотации (1-7 для колонок, F-A для строк)
			var move_str = str(col + 1) + String.chr(102 - row)
			print("Move to ", move_str)
			move_history.append(move_str)

			win_chips = win_matches(game_board, row, col, current_player)
			if win_chips:
				player_winner = current_player
				player1_timer.stop()
				player2_timer.stop()
				print("Player ", current_player, " wins!")
				_save_game_stats()
				win.emit()
			elif is_board_full():
				player_winner = PlayerState.EMPTY
				player1_timer.stop()
				player2_timer.stop()
				print("A draw")
				_save_game_stats()
				draw.emit()

			_switch_turn()
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
			
			if player1_timer.time_left > 0:
				player1_time_remaining = player1_timer.time_left
				
			player1_timer.stop()
			player2_timer.start(player2_time_remaining)
		PlayerState.PLAYER2:
			current_player = PlayerState.PLAYER1
			
			if player2_timer.time_left > 0:
				player2_time_remaining = player2_timer.time_left
				
			player2_timer.stop()
			player1_timer.start(player1_time_remaining)
	turn_changed.emit()

func _on_player1_timeout():
	if not is_game_ended():
		return
	
	player2_timer.stop()
	player_winner = PlayerState.PLAYER2
	win.emit()
	print("Player 1 has run out of time. Player 2 wins!")

func _on_player2_timeout():
	if not is_game_ended():
		return
	player1_timer.stop()
	player_winner = PlayerState.PLAYER1
	win.emit()
	print("Player 2 has run out of time. Player 1 wins!")

func _win_matches_in_direction(board: Array, col: int, row: int, direction: Vector2i, player: PlayerState) -> Array:
	var forward = _get_matches_in_direction(board, col, row, direction.y, direction.x, player)
	var backward = _get_matches_in_direction(board, col, row, -direction.y, -direction.x, player)
	backward.reverse()
	var all_matches = backward + [Vector2i(row, col)] + forward
	return all_matches

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

func _get_opponent_id(ai_player) -> String:
	var depth = ai_player.best_move_depth
	var version = ProjectSettings.get_setting("application/config/version")
	return "AiPlayer" + str(depth) + "_v" + version

func _save_game_stats():
	if (player_winner != PlayerState.PLAYER1 and player_winner != PlayerState.PLAYER2 and 
		player_winner != PlayerState.EMPTY) or not is_game_ended():
		return
		
	var config = ConfigFile.new()
	var err = config.load("user://connect4_stats.cfg")
	if err != OK and err != ERR_FILE_NOT_FOUND:
		print("Failed to load existing config: ", err)
		return

	var opponent_id = _get_opponent_id(ai_player) if ai_player != null else "Unknown"
	
	if not config.has_section(opponent_id):
		config.set_value(opponent_id, "wins", 0)
		config.set_value(opponent_id, "losses", 0)
		config.set_value(opponent_id, "draws", 0)
	
	# Определяем исход
	var outcome = "draw"
	if player_winner == users["AI"]:
		outcome = "win"
		var wins = config.get_value(opponent_id, "wins", 0)
		config.set_value(opponent_id, "wins", wins + 1)
	elif player_winner == users["PLAYER"]:
		outcome = "loss"
		var losses = config.get_value(opponent_id, "losses", 0)
		config.set_value(opponent_id, "losses", losses + 1)
	else:
		var draws = config.get_value(opponent_id, "draws", 0)
		config.set_value(opponent_id, "draws", draws + 1)
	
	# Сохраняем историю партии
	var game_id = str(Time.get_unix_time_from_system())
	config.set_value(opponent_id, "games", config.get_value(opponent_id, "games", []) + [game_id])
	config.set_value(opponent_id, game_id, {
		"moves": move_history,
		"result": outcome
	})
	
	# Сохранение в файл
	err = config.save("user://connect4_stats.cfg")
	if err != OK:
		print("Failed to save game stats: ", err)

func _load_game_stats(ai_player) -> Dictionary:
	var config = ConfigFile.new()
	var stats = {"wins": 0, "losses": 0, "draws": 0}
	
	var err = config.load("user://connect4_stats.cfg")
	if err != OK:
		print("No existing stats found or error loading: ", err)
		return stats
	
	var opponent_id = _get_opponent_id(ai_player)
	
	if config.has_section(opponent_id):
		stats["wins"] = config.get_value(opponent_id, "wins", 0)
		stats["losses"] = config.get_value(opponent_id, "losses", 0)
		stats["draws"] = config.get_value(opponent_id, "draws", 0)
	else:
		print("No stats found for opponent: ", opponent_id)
	
	return stats

func get_all_opponent_stats() -> Dictionary:
	var config = ConfigFile.new()
	var all_stats = {}
	
	var err = config.load("user://connect4_stats.cfg")
	if err != OK:
		print("No existing stats found or error loading: ", err)
		return all_stats
	
	for section in config.get_sections():
		all_stats[section] = {
			"wins": config.get_value(section, "wins", 0),
			"losses": config.get_value(section, "losses", 0),
			"draws": config.get_value(section, "draws", 0)
		}
	
	return all_stats
#endregion
