extends Node2D

const WIN_SCORE: float = 1000000
const LOSE_SCORE: float = -1000000
const CENTER_BONUS: float = 3.0

var ai_player: AiPlayer

class AiPlayer:
	signal minimax_calculated
	signal move_calculated(move)
	
	var last_moves_default = {"AI": Vector2i(-1, -1), "PLAYER": Vector2i(-1, -1)}
	var best_move_default = -1
	var current_move_index_default = -1
	var best_score_default = -INF
	
	var owner: Node
	var last_moves: Dictionary = self.last_moves_default
	var best_move: int = self.best_move_default
	var current_move_index: int = self.current_move_index_default
	var best_score: float = self.best_score_default
	var current_board: Array
	var depth: int
	
	func get_best_move(depth: int) -> int:
		self.depth = depth
		self.current_board = connect4.game_board.duplicate(true)
		var game_board_valid_moves = connect4.get_all_valid_moves()
		_calculate_best_move.call_deferred(game_board_valid_moves)
		return await move_calculated
	
	func _calculate_best_move(valid_moves: Array) -> void:
		while current_move_index < valid_moves.size():
			var board_copy = current_board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, valid_moves[current_move_index], "AI")
			last_moves["AI"] = new_last_move

			var score = await _calculate_minimax(board_copy, depth - 1, false, -INF, INF)

			if score >= best_score:
				best_score = score
				best_move = valid_moves[current_move_index]

			current_move_index += 1
		
		move_calculated.emit(best_move)
		
		last_moves = self.last_moves_default
		best_move = self.best_move_default
		current_move_index = self.current_move_index_default
		best_score = self.best_score_default

	func _calculate_minimax(board: Array, depth: int, is_maximizing: bool, alpha: float, beta: float) -> float:
		await owner.get_tree().process_frame
		
		var board_value = _evaluate_board(board)
		minimax_calculated.emit(board, board_value, is_maximizing)
		
		if _is_game_end() or depth == 0:
			return board_value

		var valid_moves = _get_valid_moves(board)

		if is_maximizing:
			var max_eval = -INF
			for col in valid_moves:
				var new_last_move = _simulate_move(board, col, "AI")
				last_moves["AI"] = new_last_move

				var eval = await _calculate_minimax(board, depth - 1, false, alpha, beta)
				max_eval = max(max_eval, eval)
				alpha = max(alpha, eval)

				if beta <= alpha:
					break
			return max_eval
		else:
			var min_eval = INF
			for col in valid_moves:
				var new_last_move = _simulate_move(board, col, "PLAYER")
				last_moves["PLAYER"] = new_last_move

				var eval = await _calculate_minimax(board, depth - 1, true, alpha, beta)
				min_eval = min(min_eval, eval)
				beta = min(beta, eval)

				if beta <= alpha:
					break
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

	func _is_game_end() -> bool:
		return (connect4.win_matches(current_board, last_moves["AI"].x, last_moves["AI"].y, connect4.users["AI"]).size() > 0 or
				connect4.win_matches(current_board, last_moves["PLAYER"].x, last_moves["PLAYER"].y, connect4.users["PLAYER"]).size() > 0 or
				_get_valid_moves(current_board).is_empty())

	func _evaluate_board(board: Array) -> float:
		if connect4.win_matches(board, last_moves["AI"].x, last_moves["AI"].y, connect4.users["AI"]).size() > 0:
			return WIN_SCORE
		if connect4.win_matches(board, last_moves["PLAYER"].x, last_moves["PLAYER"].y, connect4.users["PLAYER"]).size() > 0:
			return LOSE_SCORE

		var score: float = 0.0

		# Бонус за центр доски
		var center_col = int(connect4.cols / 2)
		var center_count = 0
		for row in range(connect4.rows):
			if board[center_col][row] == connect4.users["AI"]:
				center_count += 1
		score += center_count * CENTER_BONUS

		# Подсчёт потенциальных победных комбинаций
		for col in range(connect4.cols):
			for row in range(connect4.rows):
				if col <= connect4.cols - 4:
					var window = []
					for i in range(4):
						window.append(board[col + i][row])
					score += _evaluate_window(window)

				if row <= connect4.rows - 4:
					var window = []
					for i in range(4):
						window.append(board[col][row + i])
					score += _evaluate_window(window)

				if col <= connect4.cols - 4 and row <= connect4.rows - 4:
					var window = []
					for i in range(4):
						window.append(board[col + i][row + i])
					score += _evaluate_window(window)

				if col >= 3 and row <= connect4.rows - 4:
					var window = []
					for i in range(4):
						window.append(board[col - i][row + i])
					score += _evaluate_window(window)
		return score

	func _evaluate_window(window: Array) -> float:
		var score: float = 0.0
		var ai_count = window.count(connect4.users["AI"])
		var player_count = window.count(connect4.users["PLAYER"])
		var empty_count = window.count(connect4.PlayerState.EMPTY)

		if ai_count == 4:
			score += WIN_SCORE
		elif ai_count == 3 and empty_count == 1:
			score += 100
		elif ai_count == 2 and empty_count == 2:
			score += 10

		if player_count == 4:
			score -= LOSE_SCORE
		elif player_count == 3 and empty_count == 1:
			score -= 90

		return score

func _ready() -> void:
	connect4.turn_changed.connect(_on_turn_changed)
	ai_player = AiPlayer.new()
	ai_player.owner = get_parent()
	var visualizer = DecisionTreeVisualizer.new()
	add_child(visualizer)

func _on_turn_changed():
	if connect4.current_player == connect4.users["AI"]:
		if connect4.drop_chip_timer.time_left > 0:
			await connect4.drop_chip_timer.timeout
		
		var best_move = await ai_player.get_best_move(4)
		print(best_move)
		connect4.drop_chip("AI", best_move)
