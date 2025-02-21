extends Node2D

signal minimax_calculated
signal move_calculated(move)

const WIN_SCORE: float = 1
const LOSE_SCORE: float = -1

class ComputationState:
	var last_moves: Dictionary = {"AI": Vector2i(-1, -1), "PLAYER": Vector2i(-1, -1)}
	var best_move: int = 4
	var current_move_index: int = 0
	var best_score: float = -INF
	var current_board: Array
	var depth: int

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
	
	var game_board_valid_moves = connect4.get_all_valid_moves()
	_calculate_best_move.call_deferred(state, game_board_valid_moves)
	
	return await move_calculated

func _calculate_best_move(state: ComputationState, valid_moves: Array) -> void:
	while state.current_move_index < valid_moves.size():
		var board_copy = state.current_board.duplicate(true)
		var new_last_move = _simulate_move(board_copy, valid_moves[state.current_move_index], "AI")
		state.last_moves["AI"] = new_last_move

		var score = await _calculate_minimax(state, board_copy, state.depth - 1, false, -INF, INF)

		if score > state.best_score:
			state.best_score = score
			state.best_move = valid_moves[state.current_move_index]

		state.current_move_index += 1
		await get_tree().process_frame
	
	move_calculated.emit(state.best_move)

func _calculate_minimax(state: ComputationState, board: Array, depth: int, is_maximizing: bool, alpha: float, beta: float) -> float:
	var board_value = _evaluate_board(board, state.last_moves["AI"] if is_maximizing else state.last_moves["PLAYER"])
	
	minimax_calculated.emit(board, board_value, is_maximizing)
	
	if _is_game_end(state) or depth == 0:
		return board_value
	
	var valid_moves = _get_valid_moves(state.current_board)
	
	if is_maximizing:
		var max_eval = -INF
		for col in valid_moves:
			var board_copy = state.current_board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "AI")
			state.last_moves["AI"] = new_last_move

			var eval = await _calculate_minimax(state, board_copy, depth - 1, false, alpha, beta)
			max_eval = max(max_eval, eval)
			alpha = max(alpha, eval)
			if beta <= alpha:
				break
			await get_tree().process_frame
		return max_eval
	else:
		var min_eval = INF
		for col in valid_moves:
			var board_copy = state.current_board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "PLAYER")
			state.last_moves["PLAYER"] = new_last_move

			var eval = await _calculate_minimax(state, board_copy, depth - 1, true, alpha, beta)
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
			return Vector2i(col, row)
	return Vector2i(-1, -1)

func _get_valid_moves(board: Array) -> Array:
	var valid_moves = []
	for col in range(connect4.cols):
		if board[col][0] == connect4.PlayerState.EMPTY:
			valid_moves.append(col)
	return valid_moves

func _is_game_end(state: ComputationState) -> bool:
	if connect4.win_matches(state.current_board, state.last_moves["AI"].x, state.last_moves["AI"].y, connect4.users["AI"]) or \
	   connect4.win_matches(state.current_board, state.last_moves["PLAYER"].x, state.last_moves["PLAYER"].y, connect4.users["PLAYER"]):
		return true
	if _get_valid_moves(state.current_board).is_empty():
		return true
	return false

func _evaluate_board(board: Array, last_move: Vector2i) -> float:
	if connect4.win_matches(board, last_move.x, last_move.y, connect4.users["AI"]).size() > 0:
		return WIN_SCORE
	if connect4.win_matches(board, last_move.x, last_move.y, connect4.users["PLAYER"]).size() > 0:
		return LOSE_SCORE

	var score: float = 0.0
	var center_col = int(connect4.cols / 2)
	var center_count = 0
	for row in range(connect4.rows):
		if board[center_col][row] == connect4.users["AI"]:
			center_count += 1
	score += center_count * 3

	for col in range(connect4.cols):
		for row in range(connect4.rows):
			if col <= connect4.cols - 4:
				var window = [
					board[col][row],
					board[col + 1][row],
					board[col + 2][row],
					board[col + 3][row]
				]
				score += _evaluate_window(window)
			if row <= connect4.rows - 4:
				var window = [
					board[col][row],
					board[col][row + 1],
					board[col][row + 2],
					board[col][row + 3]
				]
				score += _evaluate_window(window)
			if col <= connect4.cols - 4 and row <= connect4.rows - 4:
				var window = [
					board[col][row],
					board[col + 1][row + 1],
					board[col + 2][row + 2],
					board[col + 3][row + 3]
				]
				score += _evaluate_window(window)
			if col >= 3 and row <= connect4.rows - 4:
				var window = [
					board[col][row],
					board[col - 1][row + 1],
					board[col - 2][row + 2],
					board[col - 3][row + 3]
				]
				score += _evaluate_window(window)
	return score

func _evaluate_window(window: Array) -> float:
	var score: float = 0.0
	var ai_count = 0
	var player_count = 0
	var empty_count = 0
	for cell in window:
		if cell == connect4.users["AI"]:
			ai_count += 1
		elif cell == connect4.users["PLAYER"]:
			player_count += 1
		else:
			empty_count += 1
	if ai_count == 4:
		score += 100
	elif ai_count == 3 and empty_count == 1:
		score += 5
	elif ai_count == 2 and empty_count == 2:
		score += 2
	if player_count == 3 and empty_count == 1:
		score -= 4
	elif player_count == 4:
		score -= 100
	return score
