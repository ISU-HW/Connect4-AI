class_name Connect4AI
extends Node

const WIN_SCORE: float = 10000.0
const LOSE_SCORE: float = -10000.0
const CENTER_BONUS: float = 5.0
const CENTER_COL: int = 4

signal tree_updated(tree_data: Dictionary, current_path: Array)
signal move_calculation_started

var game_tree: GameTreeNode
var difficult: int = 1
var max_depth: int = 1
var current_calculation_path: Array = []

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

	current_calculation_path.clear()
	game_tree = GameTreeNode.new(board, last_move, true, 0)
	_minimax(game_tree, max_depth, -INF, INF)

	var best_move = -1
	var best_score = -INF

	for child in game_tree.children:
		if child.score > best_score:
			best_score = child.score
			best_move = child.move.x

	var final_path = _get_path_to_best_move(game_tree, best_move)

	var final_tree_dict = game_tree.to_dict()
	final_tree_dict["calculation_time"] = Time.get_ticks_msec() / 1000.0 - start_time

	tree_updated.emit(final_tree_dict, final_path)

	return best_move

func _minimax(node: GameTreeNode, depth: int, alpha: float, beta: float) -> float:
	current_calculation_path.append(node.node_id)

	if depth == 0 or _is_terminal_node(node):
		node.score = _evaluate_board(node.board)
		tree_updated.emit(game_tree.to_dict(), current_calculation_path.duplicate())
		current_calculation_path.pop_back()
		return node.score

	var valid_moves = _get_valid_moves(node.board)

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
			child.parent_id = node.node_id
			node.children.append(child)

			var eval = _minimax(child, depth - 1, alpha, beta)
			child.score = eval
			max_eval = max(max_eval, eval)
			alpha = max(alpha, eval)

			if beta <= alpha:
				for i in range(valid_moves.size()):
					if i >= node.children.size():
						break
					if i > valid_moves.find(col):
						node.children[i].is_pruned = true
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
			beta = min(beta, eval)

			if beta <= alpha:
				for i in range(valid_moves.size()):
					if i >= node.children.size():
						break
					if i > valid_moves.find(col):
						node.children[i].is_pruned = true
				break

		node.score = min_eval
		node.alpha = alpha
		node.beta = beta
		tree_updated.emit(game_tree.to_dict(), current_calculation_path.duplicate())
		current_calculation_path.pop_back()
		return min_eval

func _get_path_to_best_move(node: GameTreeNode, best_col: int) -> Array:
	var path = [node.node_id]

	if node.children.size() == 0:
		return path

	var best_child = null
	for child in node.children:
		if child.move.x == best_col:
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

	var best_child = node.children[0]
	for child in node.children:
		if node.is_maximizing and child.score > best_child.score:
			best_child = child
		elif not node.is_maximizing and child.score < best_child.score:
			best_child = child

	path.append(best_child.node_id)
	path.append_array(_follow_best_path(best_child))
	return path

func _is_terminal_node(node: GameTreeNode) -> bool:
	var ai_win = not connect4.win_matches(node.board, -1, -1, connect4.users["AI"]).is_empty()
	var player_win = not connect4.win_matches(node.board, -1, -1, connect4.users["PLAYER"]).is_empty()
	var board_full = _get_valid_moves(node.board).is_empty()
	return ai_win or player_win or board_full

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

func _evaluate_board(board: Array) -> float:
	var score = 0.0

	var ai_wins = connect4.win_matches(board, -1, -1, connect4.users["AI"])
	var player_wins = connect4.win_matches(board, -1, -1, connect4.users["PLAYER"])

	if not ai_wins.is_empty():
		return WIN_SCORE
	if not player_wins.is_empty():
		return LOSE_SCORE

	for row in range(connect4.rows):
		if board[CENTER_COL][row] == connect4.users["AI"]:
			score += CENTER_BONUS

	var ai_sequences = connect4.win_matches(board, -1, -1, connect4.users["AI"])
	var player_sequences = connect4.win_matches(board, -1, -1, connect4.users["PLAYER"])

	score += ai_sequences.size() * 50.0
	score -= player_sequences.size() * 75.0

	return score
