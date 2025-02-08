class_name Connect4
extends Node

signal chip_dropped
signal not_valid_move
signal win
signal draw

var drop_chip_timer: Timer = Timer.new()
enum PlayerState { EMPTY = 0, PLAYER1 = 1, PLAYER2 = 2 }

var spawnconfig_player1 = load("res://assets/tres/spawnconfig_PLAYER1.tres")
var spawnconfig_player2 = load("res://assets/tres/spawnconfig_PLAYER2.tres")

const rows: int = 6
const cols: int = 7
var board: Array = []
var current_player: int = PlayerState.PLAYER1
var win_chips: Array
var last_move: Vector2i
var is_winner: int = 0

func _ready():
	drop_chip_timer.one_shot = true
	drop_chip_timer.wait_time = 0.5
	drop_chip_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(drop_chip_timer)
	initialize_board()

func initialize_board():
	board = []
	for row in range(rows):
		board.append([])
		for col in range(cols):
			board[row].append(PlayerState.EMPTY)

func is_valid_move(col):
	return drop_chip_timer.time_left == 0 and is_winner == 0 and board[0][col] == PlayerState.EMPTY

func drop_chip(col):
	if not is_valid_move(col):
		not_valid_move.emit()
		return false

	for row in range(rows - 1, -1, -1):
		if board[row][col] == PlayerState.EMPTY:
			drop_chip_timer.start()
			board[row][col] = current_player
			
			last_move = Vector2i(row, col)
			chip_dropped.emit(last_move, current_player)
			
			win_chips = _win_matches(row, col)
			print(win_chips)
			if win_chips:
				is_winner = current_player
				win.emit()
				print("Player ", current_player, " wins!")
			elif _is_board_full():
				current_player = PlayerState.EMPTY
				draw.emit()
				print("It's a draw!")
			_switch_turn()
			return true
	return false

func _switch_turn():
	current_player = PlayerState.PLAYER2 if current_player == PlayerState.PLAYER1 else PlayerState.PLAYER1
	
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

func get_board():
	return board

# Получение текущего хода
func get_current_player():
	return current_player
