class_name DecisionTreeVisualizer
extends Node2D

const NODE_RADIUS = 5
const VERTICAL_SPACING = 100
const HORIZONTAL_SPACING = 80

var view_rect: Rect2
var background_color: Color = Color(0.1, 0.1, 0.1, 0.5)

class TreeNode:
	var board: Array
	var score: float
	var children: Array[TreeNode]
	var position: Vector2
	var move_column: int
	var is_maximizing: bool
	var is_current_path: bool = false
	var depth: int = 0

	func _init(b: Array, s: float = 0.0, col: int = -1, max_player: bool = true):
		board = b
		score = s
		children = []
		move_column = col
		is_maximizing = max_player

var root: TreeNode
var total_width: float = 0
var max_depth: int = 0
var ai_script: Node
var current_depth: int = 3  

func _ready():
	ai_script = get_parent()
	ai_script.minimax_calculated.connect(_on_minimax_calculated)
	connect4.start.connect(_on_game_started)
	connect4.turn_changed.connect(_on_turn_changed)
	get_tree().root.size_changed.connect(_on_window_resize)
	_update_view_rect()

func _update_view_rect():
	var window_size = get_viewport_rect().size
	var rect_width = window_size.x * 0.3
	var rect_height = window_size.y * 0.3
	view_rect = Rect2(
		10,  # 10 pixels padding from right
		window_size.y - rect_height - 10,  # 10 pixels padding from bottom
		rect_width,
		rect_height
	)

func _on_window_resize():
	_update_view_rect()
	if root:
		_calculate_tree_layout()
	queue_redraw()

func _draw():
	draw_rect(view_rect, background_color)
	if root:
		_draw_tree(root)

func _draw_tree(node: TreeNode):
	if not view_rect.has_point(node.position):
		return

	for child in node.children:
		if view_rect.has_point(node.position) or view_rect.has_point(child.position):
			var line_color = Color.YELLOW if node.is_current_path and child.is_current_path else Color.WHITE
			draw_line(node.position, child.position, line_color, 2.0 if node.is_current_path else 1.0)

	var node_color = Color.GREEN if node.is_maximizing else Color.RED
	if node.is_current_path:
		node_color = node_color.lightened(0.3)
	draw_circle(node.position, NODE_RADIUS, node_color)

	var score_text = "%.1f" % node.score
	var font = ThemeDB.fallback_font
	var font_size = ThemeDB.fallback_font_size
	var text_size = font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, node.position - text_size / 2, score_text)

	if node.move_column >= 0:
		var move_text = str(node.move_column)
		var move_pos = (node.position + Vector2(0, -NODE_RADIUS - 10))
		draw_string(font, move_pos, move_text)

func _on_game_started():
	root = null
	queue_redraw()

func _on_turn_changed():
	if connect4.current_player == connect4.users["AI"]:
		_reset_current_path(root)
		queue_redraw()

func _on_minimax_calculated(board: Array, score: float, is_maximizing: bool):
	if not root:
		root = TreeNode.new(board.duplicate(true), score, -1, is_maximizing)
		_generate_complete_tree(root, current_depth)
		_calculate_tree_layout()
	
	var current_node = _find_matching_node(root, board)
	if current_node:
		current_node.is_current_path = true
		current_node.score = score
		queue_redraw()

func _generate_complete_tree(node: TreeNode, depth: int):
	if depth <= 0:
		return

	var valid_moves = _get_valid_moves(node.board)
	for move in valid_moves:
		var new_board = node.board.duplicate(true)
		var move_result = _simulate_move(new_board, move, "AI" if node.is_maximizing else "PLAYER")
		if move_result != Vector2i(-1, -1):
			var child = TreeNode.new(new_board, 0.0, move, !node.is_maximizing)
			child.depth = node.depth + 1
			node.children.append(child)
			_generate_complete_tree(child, depth - 1)

func _get_valid_moves(board: Array) -> Array:
	var valid_moves = []
	for col in range(connect4.cols):
		if board[0][col] == connect4.PlayerState.EMPTY:
			valid_moves.append(col)
	return valid_moves

func _simulate_move(board: Array, col: int, user: String) -> Vector2i:
	var player = connect4.users[user]
	for row in range(connect4.rows - 1, -1, -1):
		if board[row][col] == connect4.PlayerState.EMPTY:
			board[row][col] = player
			return Vector2i(row, col)
	return Vector2i(-1, -1)

func _find_matching_node(node: TreeNode, board: Array) -> TreeNode:
	if _boards_equal(node.board, board):
		return node
	
	for child in node.children:
		var found = _find_matching_node(child, board)
		if found:
			return found
	
	return null

func _boards_equal(board1: Array, board2: Array) -> bool:
	if board1.size() != board2.size():
		return false
	
	for i in range(board1.size()):
		if board1[i].size() != board2[i].size():
			return false
		for j in range(board1[i].size()):
			if board1[i][j] != board2[i][j]:
				return false
	
	return true

func _reset_current_path(node: TreeNode):
	if not node:
		return
	
	node.is_current_path = false
	for child in node.children:
		_reset_current_path(child)

func _calculate_tree_layout():
	if not root:
		return

	max_depth = 0
	var nodes_to_check = [root]
	while nodes_to_check:
		var node = nodes_to_check.pop_front()
		max_depth = max(max_depth, node.depth)
		nodes_to_check.append_array(node.children)

	_assign_positions(root, 
		view_rect.position.x + view_rect.size.x / 2,
		view_rect.position.y + NODE_RADIUS * 2,
		view_rect.size.x - NODE_RADIUS * 4)

func _assign_positions(node: TreeNode, x: float, y: float, available_width: float, depth: int = 0):
	node.position = Vector2(x, y)
	
	if node.children.size() > 0:
		var child_width = available_width / node.children.size()
		var total_children_width = child_width * node.children.size()
		var start_x = x - total_children_width / 2 + child_width / 2
		
		var vertical_step = min(
			VERTICAL_SPACING,
			(view_rect.size.y - NODE_RADIUS * 4) / (max_depth + 1)
		)
		
		for i in range(node.children.size()):
			var child = node.children[i]
			var child_x = start_x + i * child_width
			var child_y = y + vertical_step
			
			child_x = clamp(child_x, 
				view_rect.position.x + NODE_RADIUS * 2,
				view_rect.position.x + view_rect.size.x - NODE_RADIUS * 2)
			child_y = min(child_y, 
				view_rect.position.y + view_rect.size.y - NODE_RADIUS * 2)
			
			_assign_positions(child, child_x, child_y, child_width, depth + 1)
