extends Node2D

signal minimax_calculated
signal move_calculated(move)

const WIN_SCORE: float = 1
const LOSE_SCORE: float = -1

class ComputationState:
	var depth: int
	var best_move: int = -1
	var should_stop: bool = false
	var current_board: Array
	var valid_moves: Array
	var current_move_index: int = 0
	var best_score: float = -INF

func _ready() -> void:
	connect4.turn_changed.connect(_on_turn_changed)
	var visualizer = DecisionTreeVisualizer.new()
	add_child(visualizer)

func _on_turn_changed():
	if connect4.current_player == connect4.users["AI"]:
		if connect4.drop_chip_timer.time_left > 0:
			await connect4.drop_chip_timer.timeout
		
		var best_move = await _get_best_move(3)
		connect4.drop_chip("AI", best_move)

func _get_best_move(depth: int) -> int:
	var state = ComputationState.new()
	state.depth = depth
	
	state.current_board = connect4.game_board.duplicate(true)
	state.valid_moves = connect4.get_all_valid_moves()
	
	_calculate_move.call_deferred(state)
	
	return await move_calculated

func _calculate_move(state: ComputationState) -> void:
	while not state.should_stop and state.current_move_index < state.valid_moves.size():
		var col = state.valid_moves[state.current_move_index]
		var board_copy = state.current_board.duplicate(true)
		var new_last_move = _simulate_move(board_copy, col, "AI")
		
		var score = await _calculate_minimax(board_copy, new_last_move, state.depth - 1, false, -INF, INF)
		
		if score > state.best_score:
			state.best_score = score
			state.best_move = col
		
		state.current_move_index += 1
		await get_tree().process_frame
	
	move_calculated.emit(state.best_move)

func _calculate_minimax(board: Array, last_move: Vector2i, depth: int, is_maximizing: bool, alpha: float, beta: float) -> float:
	minimax_calculated.emit(board, _evaluate_board(board, last_move), is_maximizing)
	
	if _is_game_end(board, last_move) or depth == 0:
		return _evaluate_board(board, last_move)
	
	var valid_moves = _get_valid_moves(board)
	
	if is_maximizing:
		var max_eval = -INF
		for col in valid_moves:
			var board_copy = board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "AI")
			var eval = await _calculate_minimax(board_copy, new_last_move, depth - 1, false, alpha, beta)
			max_eval = max(max_eval, eval)
			alpha = max(alpha, eval)
			if beta <= alpha:
				break
			await get_tree().process_frame
		return max_eval
	else:
		var min_eval = INF
		for col in valid_moves:
			var board_copy = board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "PLAYER")
			var eval = await _calculate_minimax(board_copy, new_last_move, depth - 1, true, alpha, beta)
			min_eval = min(min_eval, eval)
			beta = min(beta, eval)
			if beta <= alpha:
				break
			await get_tree().process_frame
		return min_eval

func _simulate_move(board: Array, col: int, user: String) -> Vector2i:
	var player = connect4.users[user]
	for row in range(connect4.rows - 1, -1, -1):
		if board[col][row] == connect4.PlayerState.EMPTY:
			board[col][row] = player
			return Vector2i(row, col)
	return Vector2i(-1, -1)

func _get_valid_moves(board: Array) -> Array:
	var valid_moves = []
	for col in range(connect4.cols):
		if board[col][0] == connect4.PlayerState.EMPTY:
			valid_moves.append(col)
	return valid_moves

func _is_game_end(board: Array, last_move: Vector2i) -> bool:
	if connect4.win_matches(board, last_move[0], last_move[1], connect4.users["AI"]) or \
	   connect4.win_matches(board, last_move[0], last_move[1], connect4.users["PLAYER"]):
		return true
	if _get_valid_moves(board).is_empty():
		return true
	return false

func _evaluate_board(board: Array, last_move: Vector2i) -> float:
	if connect4.win_matches(board, last_move[0], last_move[1], connect4.users["AI"]):
		return WIN_SCORE
	elif connect4.win_matches(board, last_move[0], last_move[1], connect4.users["PLAYER"]):
		return LOSE_SCORE
	else:
		return 0.0
