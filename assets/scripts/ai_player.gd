extends Node2D

const WIN_SCORE: float = 1000000
const LOSE_SCORE: float = -1000000
const CENTER_BONUS: float = 3.0

var ai_player: AiPlayer
var visualizer_enable: bool = false
var depth_best_move: int
var thread: Thread

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
	var calculation_complete: bool = false
	
	func get_best_move(depth: int) -> int:
		self.depth = depth
		self.current_board = connect4.game_board.duplicate(true)
		var game_board_valid_moves = connect4.get_all_valid_moves()
		
		# Сортировка ходов
		var center_col = int(connect4.cols / 2)
		game_board_valid_moves.sort_custom(func(a, b): 
			return abs(a - center_col) < abs(b - center_col)
		)
		
		calculation_complete = false
		current_move_index = 0
		best_score = -INF
		
		owner.thread = Thread.new()
		owner.thread.start(_thread_calculate_best_move.bind(game_board_valid_moves))
		
		while not calculation_complete:
			await owner.get_tree().process_frame
		
		return best_move
	
	func _thread_calculate_best_move(valid_moves: Array) -> void:
		var thread_last_moves = last_moves.duplicate()
		var thread_best_move = best_move_default
		var thread_best_score = -INF
		var thread_board = current_board.duplicate(true)
		
		for move_idx in range(valid_moves.size()):
			var board_copy = thread_board.duplicate(true)
			var new_last_move = _simulate_move(board_copy, valid_moves[move_idx], "AI")
			thread_last_moves["AI"] = new_last_move
			
			if connect4.win_matches(board_copy, new_last_move.x, new_last_move.y, connect4.users["AI"]).size() > 0:
				thread_best_move = valid_moves[move_idx]
				break

			var score = _minimax(board_copy, depth - 1, false, -INF, INF, thread_last_moves)

			if score >= thread_best_score:
				thread_best_score = score
				thread_best_move = valid_moves[move_idx]
		
		_complete_calculation.call_deferred(thread_best_move)
		_cleanup_thread.call_deferred()
		
	func _cleanup_thread() -> void:
		if owner.thread and owner.thread.is_started():
			owner.thread.wait_to_finish()
	
	func _complete_calculation(result_move: int) -> void:
		best_move = result_move
		calculation_complete = true
		move_calculated.emit(best_move)
	
	func _minimax(board: Array, depth: int, is_maximizing: bool, alpha: float, beta: float, thread_last_moves: Dictionary) -> float:
		var board_value = _evaluate_board(board, thread_last_moves)
		minimax_calculated.emit(depth, board_value, is_maximizing, alpha, beta)
		if _is_game_end(board, thread_last_moves) or depth == 0:
			return board_value

		var valid_moves = _get_valid_moves(board)
		
		# Сортируем ходы, начиная с центра
		var center_col = int(connect4.cols / 2)
		valid_moves.sort_custom(func(a, b): 
			return abs(a - center_col) < abs(b - center_col)
		)

		if is_maximizing:
			var max_eval = -INF
			for col in valid_moves:
				var board_copy = board.duplicate(true)
				var new_last_move = _simulate_move(board_copy, col, "AI")
				
				# Сохраняем предыдущее значение для восстановления
				var prev_last_move = thread_last_moves["AI"]
				thread_last_moves["AI"] = new_last_move

				var eval = _minimax(board_copy, depth - 1, false, alpha, beta, thread_last_moves)
				
				# Восстанавливаем предыдущее значение
				thread_last_moves["AI"] = prev_last_move
				
				max_eval = max(max_eval, eval)
				alpha = max(alpha, eval)

				if beta <= alpha:
					break  # Отсечение альфа
					
			return max_eval
		else:
			var min_eval = INF
			for col in valid_moves:
				var board_copy = board.duplicate(true)
				var new_last_move = _simulate_move(board_copy, col, "PLAYER")
				
				# Сохраняем предыдущее значение для восстановления
				var prev_last_move = thread_last_moves["PLAYER"]
				thread_last_moves["PLAYER"] = new_last_move

				var eval = _minimax(board_copy, depth - 1, true, alpha, beta, thread_last_moves)
				
				# Восстанавливаем предыдущее значение
				thread_last_moves["PLAYER"] = prev_last_move
				
				min_eval = min(min_eval, eval)
				beta = min(beta, eval)

				if beta <= alpha:
					break  # Отсечение бета
					
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

	func _is_game_end(board: Array, thread_last_moves: Dictionary) -> bool:
		return (connect4.win_matches(board, thread_last_moves["AI"].x, thread_last_moves["AI"].y, connect4.users["AI"]).size() > 0 or
				connect4.win_matches(board, thread_last_moves["PLAYER"].x, thread_last_moves["PLAYER"].y, connect4.users["PLAYER"]).size() > 0 or
				_get_valid_moves(board).is_empty())

	func _evaluate_board(board: Array, thread_last_moves: Dictionary) -> float:
		if connect4.win_matches(board, thread_last_moves["AI"].x, thread_last_moves["AI"].y, connect4.users["AI"]).size() > 0:
			return WIN_SCORE
		if connect4.win_matches(board, thread_last_moves["PLAYER"].x, thread_last_moves["PLAYER"].y, connect4.users["PLAYER"]).size() > 0:
			return LOSE_SCORE

		var score: float = 0.0
		
		# 1. Оценка контроля центра (с убывающим весом)
		var center_col = int(connect4.cols / 2)
		for row in range(connect4.rows):
			if board[center_col][row] == connect4.users["AI"]:
				# Выше расположенные фишки ценнее (ближе к верху)
				score += CENTER_BONUS * (1.0 + float(connect4.rows - row) / connect4.rows)
			elif board[center_col][row] == connect4.users["PLAYER"]:
				# Штраф за контроль центра противником
				score -= CENTER_BONUS * 0.8 * (1.0 + float(connect4.rows - row) / connect4.rows)

		# 2. Оценка всей доски с весами позиций
		for col in range(connect4.cols):
			for row in range(connect4.rows):
				# Позиционный вес: центр ценнее краев
				var position_weight = 1.0 - (abs(col - center_col) / float(max(1, center_col)))
				
				# Оценка по горизонтали
				if col <= connect4.cols - 4:
					var window = []
					for i in range(4):
						window.append(board[col + i][row])
					score += _evaluate_window(window) * position_weight
					
				# Оценка по вертикали
				if row <= connect4.rows - 4:
					var window = []
					for i in range(4):
						window.append(board[col][row + i])
					score += _evaluate_window(window) * position_weight
					
				# Оценка по диагонали (↘)
				if col <= connect4.cols - 4 and row <= connect4.rows - 4:
					var window = []
					for i in range(4):
						window.append(board[col + i][row + i])
					score += _evaluate_window(window) * position_weight
					
				# Оценка по диагонали (↗)
				if col >= 3 and row <= connect4.rows - 4:
					var window = []
					for i in range(4):
						window.append(board[col - i][row + i])
					score += _evaluate_window(window) * position_weight
					
		# 3. Оценка форк-угроз
		score += _evaluate_fork_threats(board)
					
		return score

	func _evaluate_window(window: Array) -> float:
		var score: float = 0.0
		var ai_count = window.count(connect4.users["AI"])
		var player_count = window.count(connect4.users["PLAYER"])
		var empty_count = window.count(connect4.PlayerState.EMPTY)
		
		# Если в окне есть фишки обоих игроков, это не представляет угрозы
		if ai_count > 0 and player_count > 0:
			return 0.0
			
		# Оценка для AI
		if ai_count > 0 and player_count == 0:
			if ai_count == 4:
				score += WIN_SCORE
			elif ai_count == 3 and empty_count == 1:
				score += 150.0  # Повышен вес для 3 в ряд
			elif ai_count == 2 and empty_count == 2:
				score += 20.0   # Повышен вес для 2 в ряд
			elif ai_count == 1 and empty_count == 3:
				score += 1.0    # Небольшой бонус за одну фишку
				
		# Оценка для игрока (защита)
		if player_count > 0 and ai_count == 0:
			if player_count == 4:
				score -= LOSE_SCORE
			elif player_count == 3 and empty_count == 1:
				score -= 180.0  # Повышенный штраф, чтобы блокировать угрозы противника
			elif player_count == 2 and empty_count == 2:
				score -= 15.0   # Штраф за потенциальную угрозу
				
		return score
		
	func _evaluate_fork_threats(board: Array) -> float:
		var score: float = 0.0
		var threats = []
		var valid_moves = _get_valid_moves(board)
		
		# Проверка наличия форк-угроз (двойных угроз)
		for col in valid_moves:
			var temp_board = board.duplicate(true)
			var move_pos = _simulate_move(temp_board, col, "AI")
			
			if move_pos.x == -1:  # Недействительный ход
				continue
				
			# Проверяем количество угроз "3 в ряд"
			var threat_count = _count_win_threats(temp_board, move_pos, "AI")
			
			# Если создаем две или более угрозы, это форкинг
			if threat_count >= 2:
				score += 300.0
				threats.append(Vector2(col, move_pos.y))
			
			# Отменяем ход
			temp_board[move_pos.x][move_pos.y] = connect4.PlayerState.EMPTY
			
			# Теперь проверяем угрозы форкинга игрока, чтобы их блокировать
			move_pos = _simulate_move(temp_board, col, "PLAYER")
			
			if move_pos.x != -1:
				var player_threat_count = _count_win_threats(temp_board, move_pos, "PLAYER")
				
				if player_threat_count >= 2:
					score -= 350.0  # Высокий штраф за возможный форкинг противника
		
		# Бонус за создание нескольких точек форкинга
		score += min(threats.size(), 3) * 50.0
		
		return score
		
	func _count_win_threats(board: Array, pos: Vector2i, player: String) -> int:
		var threat_count = 0
		var player_state = connect4.users[player]
		
		# Проверяем все направления для поиска потенциальных "3 в ряд"
		# Горизонтальные угрозы
		for c in range(max(0, pos.x - 3), min(connect4.cols - 3, pos.x + 1)):
			var window = []
			for i in range(4):
				window.append(board[c + i][pos.y])
			if window.count(player_state) == 3 and window.count(connect4.PlayerState.EMPTY) == 1:
				threat_count += 1
		
		# Вертикальные угрозы (только вниз)
		if pos.y <= connect4.rows - 4:
			var window = []
			for i in range(4):
				window.append(board[pos.x][pos.y + i])
			if window.count(player_state) == 3 and window.count(connect4.PlayerState.EMPTY) == 1:
				threat_count += 1
		
		# Диагональные угрозы (↘)
		for offset in range(-3, 1):
			var c = pos.x + offset
			var r = pos.y + offset
			
			if c >= 0 and c + 3 < connect4.cols and r >= 0 and r + 3 < connect4.rows:
				var window = []
				for i in range(4):
					window.append(board[c + i][r + i])
				if window.count(player_state) == 3 and window.count(connect4.PlayerState.EMPTY) == 1:
					threat_count += 1
		
		# Диагональные угрозы (↗)
		for offset in range(-3, 1):
			var c = pos.x + offset
			var r = pos.y - offset
			
			if c >= 0 and c + 3 < connect4.cols and r - 3 >= 0 and r < connect4.rows:
				var window = []
				for i in range(4):
					window.append(board[c + i][r - i])
				if window.count(player_state) == 3 and window.count(connect4.PlayerState.EMPTY) == 1:
					threat_count += 1
		
		return threat_count

func _ready() -> void:
	var depth_best_move_ui = $/root/Main/start_menu/CenterContainer/Container/VBoxContainer/difficult/depth_best_move
	connect4.turn_changed.connect(_on_turn_changed)
	connect4.start.connect(_on_start.bind(depth_best_move_ui))
	ai_player = AiPlayer.new()
	ai_player.owner = self
	if visualizer_enable:
		var visualizer = DecisionTreeVisualizer.new()
		add_child(visualizer)

func _on_start(depth_best_move_ui):
	if depth_best_move_ui != null:
		depth_best_move_ui.apply()
		depth_best_move = int(depth_best_move_ui.get_line_edit().text)

func _on_turn_changed():
	if connect4.current_player == connect4.users["AI"]:
		if connect4.drop_chip_timer.time_left > 0:
			await connect4.drop_chip_timer.timeout
		if connect4.player_winner == connect4.PlayerState.EMPTY:
			var best_move = await ai_player.get_best_move(depth_best_move)
			connect4.drop_chip("AI", best_move)
