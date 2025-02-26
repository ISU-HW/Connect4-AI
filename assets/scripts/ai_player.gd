extends Node2D

const WIN_SCORE: float = 10000
const LOSE_SCORE: float = -10000
const CENTER_BONUS: float = 5.0
const CENTER_COL = int(connect4.cols / 2.0)

var ai_player: AiPlayer
var visualizer_enable: bool = false
var difficult: int
var minimax_depth: int
var thread: Thread

class AiPlayer:
	signal minimax_calculated
	signal move_calculated
	
	var last_moves_default = {"AI": Vector2i(-1, -1), "PLAYER": Vector2i(-1, -1)}
	var best_moves_default = []
	var current_move_index_default = -1
	var best_score_default = -INF
	
	var owner: Node
	var last_moves: Dictionary = self.last_moves_default
	var best_moves: Array = self.best_moves_default.duplicate()
	var current_move_index: int = self.current_move_index_default
	var best_score: float = self.best_score_default
	var current_board: Array
	var depth: int
	var calculation_complete: bool = false
	
	func get_best_move(depth: int) -> int:
		self.depth = depth
		self.current_board = connect4.game_board.duplicate(true)
		var game_board_valid_moves = connect4.get_all_valid_moves()
		
		game_board_valid_moves.sort_custom(func(a, b): 
			return abs(a - CENTER_COL) < abs(b - CENTER_COL)
		)
		
		calculation_complete = false
		current_move_index = 0
		best_score = -INF
		best_moves.clear()
		
		owner.thread = Thread.new()
		owner.thread.start(_thread_calculate_best_move.bind(game_board_valid_moves))
		
		while not calculation_complete:
			await owner.get_tree().process_frame
		
		# Случайный ход из лучших
		if best_moves.size() > 0:
			return best_moves[randi() % best_moves.size()]
		return -1 
	
	func _thread_calculate_best_move(valid_moves: Array) -> void:
		var thread_last_moves = last_moves.duplicate()
		var thread_best_moves = []
		var thread_best_score = -INF
		var thread_board = current_board.duplicate(true)
		
		var winning_move = -1
		var blocking_move = -1
		
		for move_idx in range(valid_moves.size()):
			var col = valid_moves[move_idx]
			
			var board_copy = thread_board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, col, "AI")
			if connect4.win_matches(board_copy, new_last_move.x, new_last_move.y, connect4.users["AI"]).size() > 0:
				winning_move = col
				break
			
			board_copy = thread_board.duplicate(true)
			var row = _find_row_for_move(board_copy, col)
			if row >= 0:
				board_copy[col][row] = connect4.users["PLAYER"]
				if connect4.win_matches(board_copy, col, row, connect4.users["PLAYER"]).size() > 0:
					blocking_move = col
		
		if winning_move >= 0:
			thread_best_moves = [winning_move]
		elif blocking_move >= 0:
			thread_best_moves = [blocking_move]
		else:
			for move_idx in range(valid_moves.size()):
				var col = valid_moves[move_idx]
				var board_copy = thread_board.duplicate(true)
				var new_last_move = _simulate_move(board_copy, col, "AI")
				thread_last_moves["AI"] = new_last_move
				
				var threat_bonus = _evaluate_threat(board_copy, col)
				var score = _minimax(board_copy, depth - 1, false, -INF, INF, thread_last_moves) + threat_bonus
				
				if score > thread_best_score:
					thread_best_score = score
					thread_best_moves = [col]
				elif score == thread_best_score:
					thread_best_moves.append(col)
		
		_complete_calculation.call_deferred(thread_best_moves, thread_best_score)
		_cleanup_thread.call_deferred()
		
	func _cleanup_thread() -> void:
		if owner.thread and owner.thread.is_started():
			owner.thread.wait_to_finish()
	
	func _complete_calculation(result_moves: Array, result_score: float) -> void:
		best_moves = result_moves
		best_score = result_score
		calculation_complete = true
		
		move_calculated.emit()
	
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

	func _is_game_end(board: Array, thread_last_moves: Dictionary) -> bool:
		if thread_last_moves["AI"].x >= 0 and connect4.win_matches(board, thread_last_moves["AI"].x, thread_last_moves["AI"].y, connect4.users["AI"]).size() > 0:
			return true
		if thread_last_moves["PLAYER"].x >= 0 and connect4.win_matches(board, thread_last_moves["PLAYER"].x, thread_last_moves["PLAYER"].y, connect4.users["PLAYER"]).size() > 0:
			return true
		return _get_valid_moves(board).is_empty()
		
	func _find_row_for_move(board: Array, col: int) -> int:
		for row in range(connect4.rows - 1, -1, -1):
			if board[col][row] == connect4.PlayerState.EMPTY:
				return row
		return -1
		
	func _minimax(board: Array, depth: int, is_maximizing: bool, alpha: float, beta: float, thread_last_moves: Dictionary) -> float:
		if _is_game_end(board, thread_last_moves) or depth == 0:
			return _evaluate_board(board, thread_last_moves, depth)

		var valid_moves = _get_valid_moves(board)
		
		valid_moves.sort_custom(func(a, b):
			var threat_a = _evaluate_threat(board, a)
			var threat_b = _evaluate_threat(board, b)
			
			match threat_a - threat_b:
				_: return threat_a > threat_b
				0: return abs(a - CENTER_COL) < abs(b - CENTER_COL)
		)

		if is_maximizing:
			var max_eval = -INF
			for col in valid_moves:
				var board_copy = board.duplicate(true)
				var new_last_move = _simulate_move(board_copy, col, "AI")
				
				# Предыдущее значение для восстановления хода
				var prev_last_move = thread_last_moves["AI"]
				thread_last_moves["AI"] = new_last_move

				var eval = _minimax(board_copy, depth - 1, false, alpha, beta, thread_last_moves)
				
				# Восстанавление хода
				thread_last_moves["AI"] = prev_last_move
				
				max_eval = max(max_eval, eval)
				alpha = max(alpha, eval)

				if beta <= alpha:
					break  # Отсечение альфа
				
				minimax_calculated.emit(depth, max_eval, is_maximizing, alpha, beta)
					
			return max_eval
		else:
			var min_eval = INF
			for col in valid_moves:
				var board_copy = board.duplicate(true)
				var new_last_move = _simulate_move(board_copy, col, "PLAYER")
				
				# Предыдущее значение для восстановления хода
				var prev_last_move = thread_last_moves["PLAYER"]
				thread_last_moves["PLAYER"] = new_last_move

				var eval = _minimax(board_copy, depth - 1, true, alpha, beta, thread_last_moves)
				
				# Восстанавление хода
				thread_last_moves["PLAYER"] = prev_last_move
				
				min_eval = min(min_eval, eval)
				beta = min(beta, eval)

				if beta <= alpha:
					break  # Отсечение бета
				
				minimax_calculated.emit(depth, min_eval, is_maximizing, alpha, beta)
					
			return min_eval


	func _evaluate_threat(board: Array, col: int) -> float:
		var threat_score: float = 0.0
		var board_copy = board.duplicate(true)
		
		var ai_row = _find_row_for_move(board_copy, col)
		if ai_row >= 0:
			var ai_move = Vector2i(col, ai_row)
			board_copy[col][ai_row] = connect4.users["AI"]
			
			threat_score += _count_potential_wins(board_copy, ai_move, connect4.users["AI"]) * 50
			
			var player_threats = 0
			for player_col in range(connect4.cols):
				if board_copy[player_col][0] == connect4.PlayerState.EMPTY:
					var player_row = _find_row_for_move(board_copy, player_col)
					if player_row >= 0:
						var player_board = board_copy.duplicate(true)
						player_board[player_col][player_row] = connect4.users["PLAYER"]
						
						if connect4.win_matches(player_board, player_col, player_row, connect4.users["PLAYER"]).size() > 0:
							player_threats += 1
			
			threat_score -= player_threats * 75
			
			if _check_double_win_trap(board_copy, connect4.users["PLAYER"]):
				threat_score -= 200
		
		threat_score += _check_multiple_threats(board_copy, connect4.users["AI"]) * 60
		
		var center_weight = 3.0 * (1.0 - abs(col - CENTER_COL) / float(CENTER_COL))
		threat_score += center_weight
		
		return threat_score
		
	func _count_potential_wins(board: Array, move: Vector2i, player_state) -> int:
		var potential_wins = 0
		var directions = [
			Vector2i(0, 1),   # вертикаль
			Vector2i(1, 0),   # горизонталь
			Vector2i(1, 1),   # диагональ ↘
			Vector2i(-1, 1)   # диагональ ↙
		]
		
		for dir in directions:
			for offset in range(-3, 1):
				var sequence = []
				var valid_sequence = true
				
				for i in range(4):
					var check_pos = Vector2i(move.x + (offset + i) * dir.x, move.y + (offset + i) * dir.y)
					
					# Проверка на выход за границы
					if check_pos.x < 0 or check_pos.x >= connect4.cols or check_pos.y < 0 or check_pos.y >= connect4.rows:
						valid_sequence = false
						break
					
					sequence.append(board[check_pos.x][check_pos.y])
				
				if valid_sequence:
					var player_count = sequence.count(player_state)
					var empty_count = sequence.count(connect4.PlayerState.EMPTY)
					
					# Проверяем, можно ли сделать ход в пустые клетки
					if player_count == 3 and empty_count == 1:
						var empty_index = sequence.find(connect4.PlayerState.EMPTY)
						var empty_col = move.x + (offset + empty_index) * dir.x
						
						# Проверяем, доступна ли клетка для хода
						var empty_row = move.y + (offset + empty_index) * dir.y
						if empty_row == connect4.rows - 1 or board[empty_col][empty_row + 1] != connect4.PlayerState.EMPTY:
							potential_wins += 1
		
		return potential_wins

	# Проверка на наличие двойной угрозы выигрыша (когда противник может выиграть двумя способами)
	func _check_double_win_trap(board: Array, player_state) -> bool:
		for col in range(connect4.cols):
			if board[col][0] == connect4.PlayerState.EMPTY:  # Колонка не заполнена
				var row = _find_row_for_move(board, col)
				if row >= 0:
					var board_copy = board.duplicate(true)
					board_copy[col][row] = player_state
					
					# Проверяем, есть ли у противника две возможные выигрышные позиции после этого хода
					var win_opportunities = 0
					
					for next_col in range(connect4.cols):
						if next_col != col and board_copy[next_col][0] == connect4.PlayerState.EMPTY:
							var next_row = _find_row_for_move(board_copy, next_col)
							if next_row >= 0:
								var next_board = board_copy.duplicate(true)
								next_board[next_col][next_row] = player_state
								if connect4.win_matches(next_board, next_col, next_row, player_state).size() > 0:
									win_opportunities += 1
									if win_opportunities >= 2:
										return true
		
		return false

	# Проверка на наличие нескольких угроз у игрока
	func _check_multiple_threats(board: Array, player_state) -> int:
		var threat_count = 0
		
		for col in range(connect4.cols):
			if board[col][0] == connect4.PlayerState.EMPTY:
				var row = _find_row_for_move(board, col)
				if row >= 0:
					var board_copy = board.duplicate(true)
					board_copy[col][row] = player_state
					if connect4.win_matches(board_copy, col, row, player_state).size() > 0:
						threat_count += 1
		
		return threat_count

	func _evaluate_board(board: Array, thread_last_moves: Dictionary, remaining_depth: int = 0) -> float:
		# Если AI выиграл, возвращаем высокий положительный балл с учетом глубины
		if thread_last_moves["AI"].x >= 0 and connect4.win_matches(board, thread_last_moves["AI"].x, thread_last_moves["AI"].y, connect4.users["AI"]).size() > 0:
			return WIN_SCORE * (remaining_depth + 1)
		
		# Если игрок выиграл, возвращаем высокий отрицательный балл с учетом глубины
		if thread_last_moves["PLAYER"].x >= 0 and connect4.win_matches(board, thread_last_moves["PLAYER"].x, thread_last_moves["PLAYER"].y, connect4.users["PLAYER"]).size() > 0:
			return LOSE_SCORE * (remaining_depth + 1)
		
		# Если ничья, возвращаем 0
		if _get_valid_moves(board).is_empty():
			return 0.0

		var score: float = 0.0
		
		# Бонус за контроль центра
		for row in range(connect4.rows):
			if board[CENTER_COL][row] == connect4.users["AI"]:
				score += CENTER_BONUS
		
		# Оценка последовательностей
		score += _rate_sequences(board, "horizontal")
		score += _rate_sequences(board, "vertical")
		score += _rate_sequences(board, "diagonal")
		score += _rate_sequences(board, "reverse_diagonal")
					
		return score
	
	func _rate_sequences(board: Array, seq_type: String) -> float:
		var score: float = 0.0
		var directions = {
			"horizontal": Vector2i(1, 0),
			"vertical": Vector2i(0, 1),
			"diagonal": Vector2i(1, 1),
			"reverse_diagonal": Vector2i(-1, 1)
		}
		
		var dir = directions[seq_type]
		
		var col_start = 0
		var col_end = connect4.cols
		var row_start = 0
		var row_end = connect4.rows
		
		if seq_type == "horizontal":
			col_end = connect4.cols - 3
		elif seq_type == "vertical":
			row_end = connect4.rows - 3
		elif seq_type == "diagonal":
			col_end = connect4.cols - 3
			row_end = connect4.rows - 3
		elif seq_type == "reverse_diagonal":
			col_start = 3
			row_end = connect4.rows - 3
		
		# Проверяем каждую возможную последовательность
		for col in range(col_start, col_end):
			for row in range(row_start, row_end):
				var sequence = []
				for i in range(4):
					var c = col + i * dir.x
					var r = row + i * dir.y
					if c < 0 or c >= connect4.cols or r < 0 or r >= connect4.rows:
						break
					sequence.append(board[c][r])
				
				if sequence.size() < 4:
					continue
				
				var ai_count = 0
				var player_count = 0
				var empty_count = 0
				
				for cell in sequence:
					if cell == connect4.users["AI"]:
						ai_count += 1
					elif cell == connect4.users["PLAYER"]:
						player_count += 1
					else:
						empty_count += 1
				
				# Если в последовательности есть фишки обоих игроков, она не имеет ценности
				if ai_count > 0 and player_count > 0:
					continue
				
				if ai_count > 0:
					if ai_count == 4:
						score += WIN_SCORE
					elif ai_count == 3 and empty_count == 1:
						score += 100
					elif ai_count == 2 and empty_count == 2:
						score += 10
					elif ai_count == 1 and empty_count == 3:
						score += 1
				
				if player_count > 0:
					if player_count == 4:
						score -= WIN_SCORE
					elif player_count == 3 and empty_count == 1:
						score -= 1000
					elif player_count == 2 and empty_count == 2:
						score -= 10
				
		return score

func _ready() -> void:
	randomize()  # Создание сида генератора случайных чисел
	connect4.turn_changed.connect(_on_turn_changed)
	connect4.start.connect(_on_start)
	ai_player = AiPlayer.new()
	ai_player.owner = self
	if visualizer_enable:
		var visualizer = DecisionTreeVisualizer.new()
		add_child(visualizer)

func _on_start():
	var difficult_ui = $/root/Main/start_menu/CenterContainer/Container/VBoxContainer/level/difficult
	if difficult_ui != null:
		difficult_ui.apply()
		difficult = int(difficult_ui.get_line_edit().text)
		minimax_depth = int((difficult*(difficult + 1))/2.0)

func _on_turn_changed():
	if connect4.current_player == connect4.users["AI"]:
		if connect4.drop_chip_timer.time_left > 0:
			await connect4.drop_chip_timer.timeout
		if connect4.player_winner == connect4.PlayerState.EMPTY:
			var best_move = await ai_player.get_best_move(minimax_depth)
			connect4.drop_chip("AI", best_move)
