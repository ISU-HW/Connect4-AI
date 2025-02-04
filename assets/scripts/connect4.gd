class_name Connect4
extends Node

signal chip_dropped
signal not_valid_move

var drop_chip_timer: Timer = Timer.new()
enum CellState { EMPTY = 0, PLAYER1 = 1, PLAYER2 = 2 }

const rows: int = 6
const cols: int = 7
var board: Array = []
var current_player: int = CellState.PLAYER1
var is_winner: int = 0

func _ready():
	drop_chip_timer.one_shot = true
	drop_chip_timer.autostart = true
	drop_chip_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(drop_chip_timer)
	initialize_board()

func initialize_board():
	board = []
	for row in range(rows):
		board.append([])
		for col in range(cols):
			board[row].append(CellState.EMPTY)

func is_valid_move(col):
	return drop_chip_timer.time_left == 0 and is_winner == 0 and board[0][col] == CellState.EMPTY

func drop_chip(col):
	if not is_valid_move(col):
		not_valid_move.emit()
		return false

	for row in range(rows - 1, -1, -1):
		if board[row][col] == CellState.EMPTY:
			drop_chip_timer.start()
			chip_dropped.emit(row, col, current_player)
			board[row][col] = current_player
			if _check_win(row, col):
				is_winner = current_player
				print("Player ", current_player, " wins!")
			_switch_turn()
			return true
	return false

func _switch_turn():
	current_player = CellState.PLAYER2 if current_player == CellState.PLAYER1 else CellState.PLAYER1

func _check_win(row, col):
	if _check_line(row, col, 1, 0) or \
	   _check_line(row, col, 0, 1) or \
	   _check_line(row, col, 1, 1) or \
	   _check_line(row, col, 1, -1):
		return true

func _check_line(row, col, delta_row, delta_col):
	var count = 1
	count += _count_direction(row, col, delta_row, delta_col)
	count += _count_direction(row, col, -delta_row, -delta_col)
	return count >= 4

func _count_direction(row, col, delta_row, delta_col):
	var r = row + delta_row
	var c = col + delta_col
	var count = 0
	while r >= 0 and r < rows and c >= 0 and c < cols and board[r][c] == current_player:
		count += 1
		r += delta_row
		c += delta_col
	return count

func get_board():
	return board

# Получение текущего хода
func get_current_player():
	return current_player
