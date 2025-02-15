extends Node

var board: Array[Array]
var WIN_SCORE: float = 100000.0
var LOSE_SCORE: float = -100000.0

func _ready() -> void:
	connect4.turn_changed.connect(_on_turn_changed)
	
func _on_turn_changed():
	if connect4.current_player == connect4.users["AI"]:
		if connect4.drop_chip_timer.time_left > 0:
			await connect4.drop_chip_timer.timeout
		
		print(_get_best_move(3))
		connect4.drop_chip("AI", _get_best_move(3))

func _get_best_move(depth: int) -> int:
	var best_score = -INF
	var best_column = -1
	# Получаем список допустимых ходов из текущей доски
	var valid_moves = connect4.get_all_valid_moves()
	
	for col in valid_moves:
		var board_copy = connect4.game_board.duplicate(true)
		_simulate_move(board_copy, col, "AI")
		var score = _minimax(board_copy, connect4.last_move, depth - 1, false, -INF, INF)
		if score > best_score:
			best_score = score
			best_column = col
	
	return best_column
	
func _simulate_move(board: Array, col: int, user: String) -> Vector2i:
	var player = connect4.users[user]
	for row in range(connect4.rows - 1, -1, -1):
		if board[row][col] == connect4.PlayerState.EMPTY:
			board[row][col] = player
			return Vector2i(row, col)
	return Vector2i(-1, -1)
func _minimax(board: Array, last_move: Vector2i, depth: int, is_maximizing: bool, alpha: float, beta: float) -> float:
	if is_game_end(board, last_move) or depth == 0:
		return evaluate_board(board, last_move)

	var valid_moves = _get_valid_moves(board)
	if is_maximizing:
		var max_eval = -INF
		for col in valid_moves:
			var board_copy = board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "AI")  # Получаем новый last_move
			var eval = _minimax(board_copy, new_last_move, depth - 1, false, alpha, beta)
			max_eval = max(max_eval, eval)
			alpha = max(alpha, eval)
			if beta <= alpha:
				break
		return max_eval
	else:
		var min_eval = INF
		for col in valid_moves:
			var board_copy = board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "PLAYER")
			var eval = _minimax(board_copy, new_last_move, depth - 1, true, alpha, beta)
			min_eval = min(min_eval, eval)
			beta = min(beta, eval)
			if beta <= alpha:
				break
		return min_eval

func _get_valid_moves(board: Array) -> Array:
	var valid_moves = []
	for col in range(connect4.cols):
		if board[0][col] == connect4.PlayerState.EMPTY:
			valid_moves.append(col)
	return valid_moves

func is_game_end(board: Array, last_move: Vector2i) -> bool:
	if connect4.win_matches(board, last_move[0], last_move[1], connect4.users["AI"]) or connect4.win_matches(board, last_move[0], last_move[1], connect4.users["PLAYER"]):
		return true
	if _get_valid_moves(board).is_empty():
		return true
	return false

func evaluate_board(board: Array, last_move: Vector2i) -> float:
	if connect4.win_matches(board, last_move[0], last_move[1], connect4.users["AI"]):
		return WIN_SCORE
	elif connect4.win_matches(board, last_move[0], last_move[1], connect4.users["PLAYER"]):
		return LOSE_SCORE
	else:
		return 0.0
