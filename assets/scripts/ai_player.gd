class_name Connect4AI
extends Node

const WIN_SCORE: float = 10000.0
const LOSE_SCORE: float = -10000.0
const CENTER_BONUS: float = 5.0
const CENTER_COL: int = 4

signal minimax_calculated
signal move_calculation_started
signal move_calculated(best_move: int)
signal tree_visualization_ready(tree_data: Dictionary)

var game_tree: GameTreeNode
var difficult: int = 1
var max_depth: int = 1

class GameTreeNode:
	var board: Array[Array]
	var move: Vector2i
	var children: Array
	var score: float
	var is_maximizing: bool
	var depth: int
	var alpha: float
	var beta: float
	
	func _init(initial_board: Array[Array], initial_move: Vector2i = Vector2i(-1, -1), maximizing: bool = true, current_depth: int = 0, current_alpha: float = -INF, current_beta: float = INF):
		board = initial_board.duplicate(true)
		move = initial_move
		children = []
		score = 0.0
		is_maximizing = maximizing
		depth = current_depth
		alpha = current_alpha
		beta = current_beta


func get_best_move(board: Array[Array], last_move: Vector2i) -> int:
	max_depth = (difficult * 2) - 1
	max_depth = max(1, min(max_depth, 9))
	
	move_calculation_started.emit()
	
	var best_move = find_best_move(board, last_move)
	
	move_calculated.emit(best_move)
	return best_move

func generate_game_tree(initial_board: Array[Array], last_move: Vector2i, max_tree_depth: int) -> GameTreeNode:
	var root_node = GameTreeNode.new(initial_board, last_move, true, 0)
	_expand_game_tree(root_node, max_tree_depth)
	return root_node

func _expand_game_tree(node: GameTreeNode, remaining_depth: int) -> void:
	if remaining_depth <= 0 or _is_terminal_node(node):
		node.score = _evaluate_board(node.board)
		return
	
	var valid_moves = _get_valid_moves(node.board)
	for col in valid_moves:
		var child_board = node.board.duplicate(true)
		var player_state = connect4.users["AI"] if node.is_maximizing else connect4.users["PLAYER"]
		
		var row = _find_next_available_row(child_board, col)
		if row == -1:
			continue  # Skip invalid move (shouldn't happen as valid_moves are checked)
		child_board[col][row] = player_state
		
		var child_node = GameTreeNode.new(
			child_board, 
			Vector2i(col, row), 
			not node.is_maximizing, 
			node.depth + 1,
			node.alpha,
			node.beta
		)
		
		_expand_game_tree(child_node, remaining_depth - 1)
		
		if node.is_maximizing:
			if child_node.score > node.alpha:
				node.alpha = child_node.score
			if node.beta <= node.alpha:
				break  # Alpha cutoff
		else:
			if child_node.score < node.beta:
				node.beta = child_node.score
			if node.beta <= node.alpha:
				break  # Beta cutoff
		
		node.children.append(child_node)
	
	if node.children:
		node.score = _max_child_score(node) if node.is_maximizing else _min_child_score(node)
	else:
		node.score = _evaluate_board(node.board)

func find_best_move(board: Array[Array], last_move: Vector2i) -> int:
	game_tree = generate_game_tree(board, last_move, max_depth)
	var best_moves = []
	var best_score = -INF
	
	for child in game_tree.children:
		if child.score > best_score:
			best_score = child.score
			best_moves = [child.move.x]
		elif child.score == best_score:
			best_moves.append(child.move.x)
	
	# Randomly select from equally good moves
	return best_moves[randi() % best_moves.size()] if best_moves else -1

func _max_child_score(node: GameTreeNode) -> float:
	var max_child = node.children[0]
	for child in node.children:
		max_child = child if child.score > max_child.score else max_child
	return max_child.score

func _min_child_score(node: GameTreeNode) -> float:
	var min_child = node.children[0]
	for child in node.children:
		min_child = child if child.score < min_child.score else min_child
	return min_child.score

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
	
	# Win/Lose conditions using win_matches
	var ai_wins = connect4.win_matches(board, -1, -1, connect4.users["AI"])
	var player_wins = connect4.win_matches(board, -1, -1, connect4.users["PLAYER"])
	
	if not ai_wins.is_empty():
		return WIN_SCORE
	if not player_wins.is_empty():
		return LOSE_SCORE
	
	# Center column preference
	for row in range(connect4.rows):
		if board[CENTER_COL][row] == connect4.users["AI"]:
			score += CENTER_BONUS
	
	var ai_sequences = connect4.win_matches(board, -1, -1, connect4.users["AI"])
	var player_sequences = connect4.win_matches(board, -1, -1, connect4.users["PLAYER"])
	
	score += ai_sequences.size() * 50.0
	score -= player_sequences.size() * 75.0
	
	return score
