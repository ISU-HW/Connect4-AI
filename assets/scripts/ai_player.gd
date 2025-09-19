class_name Connect4AI
extends Node

const WIN_SCORE: float = 10000.0
const LOSE_SCORE: float = -10000.0
const CENTER_BONUS: float = 5.0
const CENTER_COL: int = 3

signal tree_updated(tree_data: Dictionary, current_path: Array)
signal move_calculation_started

var game_tree: GameTreeNode
var difficult: int = 1
var max_depth: int = 1
var current_calculation_path: Array = []
var nodes_evaluated: int = 0
var nodes_pruned: int = 0

@onready var difficult_ui: SpinBox = $/root/Main/start_menu/CenterContainer/Container/VBoxContainer/level/difficult

class GameTreeNode:
	var board: Array[Array]
	var move: Vector2i
	var children: Array
	var score: float
	var is_maximizing: bool
	var depth: int
	var alpha: float
	var beta: float
	var is_pruned: bool = false
	var node_id: String = ""
	var parent_id: String = ""

	func _init(initial_board: Array[Array], initial_move: Vector2i = Vector2i(-1, -1), maximizing: bool = true, current_depth: int = 0, current_alpha: float = -INF, current_beta: float = INF):
		board = initial_board.duplicate(true)
		move = initial_move
		children = []
		score = 0.0
		is_maximizing = maximizing
		depth = current_depth
		alpha = current_alpha
		beta = current_beta
		node_id = str(randi())

	func to_dict() -> Dictionary:
		var result = {
			"board": board,
			"move": move,
			"score": score,
			"is_maximizing": is_maximizing,
			"depth": depth,
			"alpha": alpha,
			"beta": beta,
			"is_pruned": is_pruned,
			"id": node_id,
			"parent_id": parent_id,
			"children": []
		}

		for child in children:
			result["children"].append(child.to_dict())

		return result

func _ready() -> void:
	connect4.start.connect(_on_start)

func _on_start():
	if difficult_ui != null:
		difficult_ui.apply()
		difficult = int(difficult_ui.get_line_edit().text)

func get_best_move(board: Array[Array], last_move: Vector2i) -> int:
	move_calculation_started.emit()

	max_depth = (difficult * 2) - 1
	max_depth = max(1, min(max_depth, 9))

	var start_time = Time.get_ticks_msec() / 1000.0
	nodes_evaluated = 0
	nodes_pruned = 0

	current_calculation_path.clear()
	game_tree = GameTreeNode.new(board, last_move, true, 0)
	
	# КРИТИЧЕСКИ ВАЖНО: Сначала проверяем немедленные выигрышные ходы!
	var immediate_win = _find_immediate_win(board)
	if immediate_win >= 0:
		print("Найден немедленный выигрышный ход: ", immediate_win)
		
		# Создаем минимальное дерево для визуализации
		var win_child = GameTreeNode.new(board, Vector2i(immediate_win, 0), false, 1)
		win_child.score = WIN_SCORE
		win_child.parent_id = game_tree.node_id
		game_tree.children.append(win_child)
		game_tree.score = WIN_SCORE
		
		var final_tree_dict = game_tree.to_dict()
		final_tree_dict["calculation_time"] = Time.get_ticks_msec() / 1000.0 - start_time
		tree_updated.emit(final_tree_dict, [game_tree.node_id, win_child.node_id])
		
		return immediate_win
	
	# Проверяем блокировку выигрыша противника
	var block_move = _find_block_opponent_win(board)
	if block_move >= 0:
		print("Нужно заблокировать ход противника: ", block_move)
	
	_minimax(game_tree, max_depth, -INF, INF)

	var best_move = -1
	var best_score = -INF

	for child in game_tree.children:
		if child.score > best_score:
			best_score = child.score
			best_move = child.move.x

	# Если нет выигрышного хода, предпочитаем блокирующий
	if best_score < WIN_SCORE * 0.9 and block_move >= 0:
		print("Выбираю блокирующий ход: ", block_move)
		best_move = block_move

	var final_path = _get_path_to_best_move(game_tree, best_move)

	var final_tree_dict = game_tree.to_dict()
	final_tree_dict["calculation_time"] = Time.get_ticks_msec() / 1000.0 - start_time
	final_tree_dict["nodes_evaluated"] = nodes_evaluated
	final_tree_dict["nodes_pruned"] = nodes_pruned

	tree_updated.emit(final_tree_dict, final_path)

	print("Лучший ход найден: колонка ", best_move, " с оценкой ", best_score)
	return best_move

# НОВАЯ ФУНКЦИЯ: Поиск немедленного выигрышного хода
func _find_immediate_win(board: Array[Array]) -> int:
	var valid_moves = _get_valid_moves(board)
	
	for col in valid_moves:
		var test_board = board.duplicate(true)
		var row = _find_next_available_row(test_board, col)
		if row == -1:
			continue
			
		test_board[col][row] = connect4.users["AI"]
		
		# Проверяем выигрыш
		if not connect4.win_matches(test_board, col, row, connect4.users["AI"]).is_empty():
			return col
	
	return -1

# НОВАЯ ФУНКЦИЯ: Поиск хода для блокировки победы противника
func _find_block_opponent_win(board: Array[Array]) -> int:
	var valid_moves = _get_valid_moves(board)
	
	for col in valid_moves:
		var test_board = board.duplicate(true)
		var row = _find_next_available_row(test_board, col)
		if row == -1:
			continue
			
		test_board[col][row] = connect4.users["PLAYER"]
		
		# Если противник может выиграть этим ходом, блокируем его
		if not connect4.win_matches(test_board, col, row, connect4.users["PLAYER"]).is_empty():
			return col
	
	return -1

func _minimax(node: GameTreeNode, depth: int, alpha: float, beta: float) -> float:
	nodes_evaluated += 1
	current_calculation_path.append(node.node_id)

	# Базовый случай: достигнута максимальная глубина или терминальный узел
	if depth == 0 or _is_terminal_node(node):
		node.score = _evaluate_board(node.board, node.move)
		tree_updated.emit(game_tree.to_dict(), current_calculation_path.duplicate())
		current_calculation_path.pop_back()
		return node.score

	var valid_moves = _get_valid_moves(node.board)
	
	# Сортируем ходы для лучшего отсечения (центральные колонки первыми)
	valid_moves = _order_moves(valid_moves, node.board, node.is_maximizing)

	if node.is_maximizing:
		var max_eval = -INF
		
		for col in valid_moves:
			var child_board = node.board.duplicate(true)
			var row = _find_next_available_row(child_board, col)
			if row == -1:
				continue

			child_board[col][row] = connect4.users["AI"]
			var child = GameTreeNode.new(
				child_board,
				Vector2i(col, row),
				false,
				node.depth + 1,
				alpha,
				beta
			)
			child.parent_id = node.node_id  # ИСПРАВЛЕНА ОПЕЧАТКА
			node.children.append(child)

			var eval = _minimax(child, depth - 1, alpha, beta)
			child.score = eval
			max_eval = max(max_eval, eval)
			
			if eval > alpha:
				alpha = eval
			
			if beta <= alpha:
				# Отмечаем оставшиеся ходы как отсеченные
				for remaining_col in valid_moves.slice(valid_moves.find(col) + 1):
					var pruned_child = GameTreeNode.new(
						node.board.duplicate(true),
						Vector2i(remaining_col, -1),
						false,
						node.depth + 1
					)
					pruned_child.parent_id = node.node_id
					pruned_child.is_pruned = true
					pruned_child.score = -INF
					node.children.append(pruned_child)
					nodes_pruned += 1
				
				print("Альфа-отсечение на глубине ", node.depth, ": α=", alpha, " β=", beta)
				break

		node.score = max_eval
		node.alpha = alpha
		node.beta = beta
		tree_updated.emit(game_tree.to_dict(), current_calculation_path.duplicate())
		current_calculation_path.pop_back()
		return max_eval
		
	else:
		var min_eval = INF
		
		for col in valid_moves:
			var child_board = node.board.duplicate(true)
			var row = _find_next_available_row(child_board, col)
			if row == -1:
				continue

			child_board[col][row] = connect4.users["PLAYER"]
			var child = GameTreeNode.new(
				child_board,
				Vector2i(col, row),
				true,
				node.depth + 1,
				alpha,
				beta
			)
			child.parent_id = node.node_id
			node.children.append(child)

			var eval = _minimax(child, depth - 1, alpha, beta)
			child.score = eval
			min_eval = min(min_eval, eval)
			
			if eval < beta:
				beta = eval
			
			if beta <= alpha:
				for remaining_col in valid_moves.slice(valid_moves.find(col) + 1):
					var pruned_child = GameTreeNode.new(
						node.board.duplicate(true),
						Vector2i(remaining_col, -1),
						true,
						node.depth + 1
					)
					pruned_child.parent_id = node.node_id
					pruned_child.is_pruned = true
					pruned_child.score = INF
					node.children.append(pruned_child)
					nodes_pruned += 1
				
				print("Бета-отсечение на глубине ", node.depth, ": α=", alpha, " β=", beta)
				break

		node.score = min_eval
		node.alpha = alpha
		node.beta = beta
		tree_updated.emit(game_tree.to_dict(), current_calculation_path.duplicate())
		current_calculation_path.pop_back()
		return min_eval

# УЛУЧШЕННАЯ ЭВРИСТИКА УПОРЯДОЧИВАНИЯ ХОДОВ
func _order_moves(moves: Array, board: Array, is_maximizing: bool) -> Array:
	var move_scores = []
	
	for col in moves:
		var score = 0
		
		# Приоритет центральным колонкам
		var distance_from_center = abs(col - CENTER_COL)
		score += (4 - distance_from_center) * 10
		
		var test_board = board.duplicate(true)
		var row = _find_next_available_row(test_board, col)
		if row != -1:
			# Проверяем немедленную победу для текущего игрока
			var player = connect4.users["AI"] if is_maximizing else connect4.users["PLAYER"]
			test_board[col][row] = player
			
			if not connect4.win_matches(test_board, col, row, player).is_empty():
				score += 10000  # Максимальный приоритет для выигрышного хода
			
			# Проверяем блокировку победы противника
			test_board[col][row] = connect4.users["PLAYER"] if is_maximizing else connect4.users["AI"]
			var opponent = connect4.users["PLAYER"] if is_maximizing else connect4.users["AI"]
			
			if not connect4.win_matches(test_board, col, row, opponent).is_empty():
				score += 1000  # Высокий приоритет для блокирующего хода
			
			# Бонус за создание возможностей
			score += _evaluate_potential_threats(test_board, col, row, player)
		
		move_scores.append({"col": col, "score": score})
	
	# Сортируем по убыванию оценки
	move_scores.sort_custom(func(a, b): return a.score > b.score)
	
	var ordered_moves = []
	for move_data in move_scores:
		ordered_moves.append(move_data.col)
	
	return ordered_moves

# НОВАЯ ФУНКЦИЯ: Оценка потенциальных угроз
func _evaluate_potential_threats(board: Array, col: int, row: int, player: int) -> int:
	var threats = 0
	
	# Проверяем все направления для поиска потенциальных линий
	var directions = [
		Vector2i(1, 0),   # горизонталь
		Vector2i(0, 1),   # вертикаль  
		Vector2i(1, 1),   # диагональ /
		Vector2i(1, -1)   # диагональ \
	]
	
	for direction in directions:
		var count = 1  # Считаем поставленную фишку
		
		# Считаем в одну сторону
		var pos = Vector2i(col, row) + direction
		while pos.x >= 0 and pos.x < connect4.cols and pos.y >= 0 and pos.y < connect4.rows:
			if board[pos.x][pos.y] == player:
				count += 1
				pos += direction
			else:
				break
		
		# Считаем в другую сторону
		pos = Vector2i(col, row) - direction
		while pos.x >= 0 and pos.x < connect4.cols and pos.y >= 0 and pos.y < connect4.rows:
			if board[pos.x][pos.y] == player:
				count += 1
				pos -= direction
			else:
				break
		
		# Оцениваем угрозу по количеству подряд идущих фишек
		match count:
			3: threats += 50  # Три в ряд - серьезная угроза
			2: threats += 10  # Два в ряд - потенциальная угроза
			1: threats += 1   # Одиночная фишка
	
	return threats

func _get_path_to_best_move(node: GameTreeNode, best_col: int) -> Array:
	var path = [node.node_id]

	if node.children.size() == 0:
		return path

	var best_child = null
	for child in node.children:
		if child.move.x == best_col and not child.is_pruned:
			best_child = child
			break

	if best_child:
		path.append(best_child.node_id)
		path.append_array(_follow_best_path(best_child))

	return path

func _follow_best_path(node: GameTreeNode) -> Array:
	var path = []

	if node.children.size() == 0:
		return path

	var best_child = null
	for child in node.children:
		if child.is_pruned:
			continue
			
		if best_child == null:
			best_child = child
		elif node.is_maximizing and child.score > best_child.score:
			best_child = child
		elif not node.is_maximizing and child.score < best_child.score:
			best_child = child

	if best_child:
		path.append(best_child.node_id)
		path.append_array(_follow_best_path(best_child))
	
	return path

# ИСПРАВЛЕННАЯ ПРОВЕРКА ТЕРМИНАЛЬНЫХ УЗЛОВ
func _is_terminal_node(node: GameTreeNode) -> bool:
	# Проверяем последний сделанный ход на победу
	if node.move.x >= 0 and node.move.y >= 0:
		var ai_win = not connect4.win_matches(node.board, node.move.x, node.move.y, connect4.users["AI"]).is_empty()
		var player_win = not connect4.win_matches(node.board, node.move.x, node.move.y, connect4.users["PLAYER"]).is_empty()
		
		if ai_win or player_win:
			return true
	
	# Проверяем заполненность доски
	var board_full = _get_valid_moves(node.board).is_empty()
	return board_full

func _get_valid_moves(board: Array) -> Array:
	var moves = []
	for col in range(connect4.cols):
		if board[col][0] == connect4.PlayerState.EMPTY:
			moves.append(col)
	return moves

func _find_next_available_row(board: Array, col: int) -> int:
	for row in range(connect4.rows - 1, -1, -1):
		if board[col][row] == connect4.PlayerState.EMPTY:
			return row
	return -1

# ЗНАЧИТЕЛЬНО УЛУЧШЕННАЯ ОЦЕНОЧНАЯ ФУНКЦИЯ
func _evaluate_board(board: Array, last_move: Vector2i = Vector2i(-1, -1)) -> float:
	var score = 0.0

	# КРИТИЧЕСКИ ВАЖНО: Проверка на выигрыш/поражение
	if last_move.x >= 0 and last_move.y >= 0:
		var ai_wins = connect4.win_matches(board, last_move.x, last_move.y, connect4.users["AI"])
		var player_wins = connect4.win_matches(board, last_move.x, last_move.y, connect4.users["PLAYER"])

		if not ai_wins.is_empty():
			return WIN_SCORE
		if not player_wins.is_empty():
			return LOSE_SCORE

	# Глобальная проверка на выигрыш (на всякий случай)
	for col in range(connect4.cols):
		for row in range(connect4.rows):
			if board[col][row] != connect4.PlayerState.EMPTY:
				var player = board[col][row]
				if not connect4.win_matches(board, col, row, player).is_empty():
					if player == connect4.users["AI"]:
						return WIN_SCORE
					else:
						return LOSE_SCORE

	# Центральный бонус
	for row in range(connect4.rows):
		if board[CENTER_COL][row] == connect4.users["AI"]:
			score += CENTER_BONUS * 2  # Увеличиваем бонус
		elif board[CENTER_COL][row] == connect4.users["PLAYER"]:
			score -= CENTER_BONUS

	# Оценка потенциальных линий
	score += _evaluate_all_lines(board, connect4.users["AI"]) * 10
	score -= _evaluate_all_lines(board, connect4.users["PLAYER"]) * 12

	# Контроль центра
	for col in [CENTER_COL - 1, CENTER_COL + 1]:
		if col >= 0 and col < connect4.cols:
			for row in range(connect4.rows):
				if board[col][row] == connect4.users["AI"]:
					score += 2
				elif board[col][row] == connect4.users["PLAYER"]:
					score -= 2

	return score

# НОВАЯ ФУНКЦИЯ: Полная оценка всех возможных линий
func _evaluate_all_lines(board: Array, player: int) -> float:
	var total_score = 0.0
	
	# Проверяем все возможные окна 4x1 для поиска потенциальных линий
	for col in range(connect4.cols):
		for row in range(connect4.rows):
			# Горизонтальные линии
			if col + 3 < connect4.cols:
				total_score += _evaluate_line_segment(board, col, row, 1, 0, player)
			
			# Вертикальные линии
			if row + 3 < connect4.rows:
				total_score += _evaluate_line_segment(board, col, row, 0, 1, player)
			
			# Диагональные линии (вправо-вниз)
			if col + 3 < connect4.cols and row + 3 < connect4.rows:
				total_score += _evaluate_line_segment(board, col, row, 1, 1, player)
			
			# Диагональные линии (влево-вниз)
			if col - 3 >= 0 and row + 3 < connect4.rows:
				total_score += _evaluate_line_segment(board, col, row, -1, 1, player)
	
	return total_score

func _evaluate_line_segment(board: Array, start_col: int, start_row: int, delta_col: int, delta_row: int, player: int) -> float:
	var player_count = 0
	var empty_count = 0
	var opponent_count = 0
	var opponent = connect4.users["PLAYER"] if player == connect4.users["AI"] else connect4.users["AI"]
	
	for i in range(4):
		var col = start_col + i * delta_col
		var row = start_row + i * delta_row
		
		if board[col][row] == player:
			player_count += 1
		elif board[col][row] == connect4.PlayerState.EMPTY:
			empty_count += 1
		else:
			opponent_count += 1
	
	# Если есть фишки противника, линия заблокирована
	if opponent_count > 0:
		return 0.0
	
	# Оценка зависит от количества фишек игрока
	match player_count:
		3: return 100.0  # Три в ряд - очень хорошо
		2: return 20.0   # Два в ряд - хорошо
		1: return 2.0    # Одна фишка - небольшой бонус
		_: return 0.0
