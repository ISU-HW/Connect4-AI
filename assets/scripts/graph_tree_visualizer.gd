extends ReferenceRect
class_name GraphVisualizationTree

signal performance_stats_updated(stats: Dictionary)

class TreeNode:
	var board: Array
	var score: float
	var move: Vector2i
	var is_maximizing: bool
	var depth: int
	var is_pruned: bool
	var is_current_path: bool = false  # Added for highlighting current path
	var children: Array[TreeNode] = []
	var parent: TreeNode = null
	var alpha: float = -INF  # Added for tooltip display
	var beta: float = INF  # Added for tooltip display
	var calculation_time: float = 0.0  # Added for tooltip display
	var board_hash: String = ""  # Added for node identification
	
	func _init(b: Array, s: float, m: Vector2i, max_player: bool, d: int, pruned: bool = false):
		board = b.duplicate(true)
		score = s
		move = m
		is_maximizing = max_player
		depth = d
		is_pruned = pruned
	
	# Added method for tooltip content
	func get_tooltip_text() -> String:
		var text = "Score: %.2f" % score
		text += "\nCol: %d, Row: %d" % [move.x, move.y]
		text += "\nDepth: %d" % depth
		if calculation_time > 0:
			text += "\nCalc time: %.3fs" % calculation_time
		text += "\nPruned: %s" % ("Yes" if is_pruned else "No")
		text += "\nPlayer: %s" % ("MAX" if is_maximizing else "MIN")
		text += "\nAlpha: %.2f, Beta: %.2f" % [alpha, beta]
		text += "\nChildren: %d" % children.size()
		return text

var root_node: TreeNode = null
var current_nodes: Array[TreeNode] = []
var node_size: Vector2 = Vector2(15, 15)
var horizontal_spacing: float = 30.0
var vertical_spacing: float = 70.0
var node_font: Font
var line_width: float = 2.0
var max_visible_depth: int = 9
var current_depth: int = 0
var show_pruned_nodes: bool = true
var show_values: bool = true
var show_calculation: bool = false
var pending_updates: Array = []

var maximizer_color: Color = Color(0.2, 0.7, 0.2)
var minimizer_color: Color = Color(0.7, 0.2, 0.2)
var pruned_color: Color = Color(0.5, 0.5, 0.5, 0.7)
var current_path_color: Color = Color(1.0, 0.8, 0.2)
var text_color: Color = Color(1.0, 1.0, 1.0)
var line_color: Color = Color(0.4, 0.4, 0.4)

# Tree layout
var layout_dirty: bool = true
var node_positions: Dictionary = {}
var layout_width: float = 0.0
var layout_height: float = 0.0
var pan_offset: Vector2 = Vector2(50, 50)  # Starting with some padding
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

# Tooltip variables - added from DecisionTreeVisualizer
var hovered_node: TreeNode = null
var tooltip_font: Font
var tooltip_font_size: int = 14
var tooltip_background_color: Color = Color(0.1, 0.1, 0.1, 0.9)
var tooltip_text_color: Color = Color.WHITE
var tooltip_padding: Vector2 = Vector2(10, 10)

var performance_stats = {
	"nodes_explored": 0,
	"nodes_pruned": 0,
	"calculation_time": 0.0,
	"max_depth": 0
}
var last_calculation_time: float = 0.0
var current_path_nodes: Array[TreeNode] = []
var visible_nodes: Array[TreeNode] = []
var node_map = {}
var is_calculating: bool = false

func _ready() -> void:
	node_font = ThemeDB.fallback_font
	tooltip_font = ThemeDB.fallback_font
	set_process_input(true)
	
	performance_stats_updated.emit(performance_stats)
	
	connect4.ai_player.minimax_calculated.connect(_on_minimax_calculated)
	connect4.ai_player.move_calculated.connect(_on_move_calculated)
	connect4.ai_player.move_calculation_started.connect(_on_calculation_started)
	
	var pruned_checkbox = find_gui_element("show_pruned_nodes")
	if pruned_checkbox:
		pruned_checkbox.toggled.connect(_on_show_pruned_toggled)
		
	var values_checkbox = find_gui_element("show_values")
	if values_checkbox:
		values_checkbox.toggled.connect(_on_show_values_toggled)
	
	var calculation_checkbox = find_gui_element("show_calculation") 
	if calculation_checkbox:
		calculation_checkbox.toggled.connect(_on_show_calculation_toggled)
	
	var v_scrollbar = find_gui_element("VScrollBar")
	if v_scrollbar:
		v_scrollbar.value_changed.connect(_on_v_scrollbar_value_changed)
	
	var h_scrollbar = find_gui_element("HScrollBar")
	if h_scrollbar:
		h_scrollbar.value_changed.connect(_on_h_scrollbar_value_changed)
	
	# Make sure visualization is visible - one potential fix for the display issue
	modulate.a = 1.0
	visible = true
	

func find_gui_element(path: String) -> Node:
	var node = $/root/Main/visualizer_menu.get_node_or_null(path)
	return node

func _on_show_pruned_toggled(enabled: bool) -> void:
	show_pruned_nodes = enabled
	layout_dirty = true
	queue_redraw()

func _on_show_values_toggled(enabled: bool) -> void:
	show_values = enabled
	queue_redraw()
	

func _on_show_calculation_toggled(enabled: bool) -> void:
	show_calculation = enabled
	if enabled and pending_updates.size() > 0:
		# Apply pending updates if we enable calculation display
		for update in pending_updates:
			_apply_node_update(update.board, update.score, update.move, update.is_maximizing, update.depth, update.is_pruned)
		pending_updates.clear()
		layout_dirty = true
		queue_redraw()

func _on_v_scrollbar_value_changed(value: float) -> void:
	# Update pan offset based on scrollbar value
	var v_scroll_offset = value * size.y
	pan_offset.y = -v_scroll_offset
	queue_redraw()

func _on_h_scrollbar_value_changed(value: float) -> void:
	# Update pan offset based on horizontal scrollbar value
	var h_scroll_offset = value * size.x
	pan_offset.x = -h_scroll_offset + 50  # Keep the initial padding
	queue_redraw()

func update_scrollbars() -> void:
	update_vertical_scrollbar()
	update_horizontal_scrollbar()

func update_vertical_scrollbar() -> void:
	var v_scrollbar = find_gui_element("VScrollBar")
	if v_scrollbar:
		var view_height = size.y
		
		# Calculate ratio of content height to view height
		var ratio = layout_height / view_height
		
		# Only enable scrolling if content is larger than view
		if ratio > 1.0:
			v_scrollbar.max_value = ratio
			v_scrollbar.page = 1.0 / ratio
			v_scrollbar.visible = true
		else:
			v_scrollbar.max_value = 1.0
			v_scrollbar.value = 0.0
			v_scrollbar.visible = false

func update_horizontal_scrollbar() -> void:
	var h_scrollbar = find_gui_element("HScrollBar")
	if h_scrollbar:
		var view_width = size.x
		
		# Calculate ratio of content width to view width
		var ratio = layout_width / view_width
		
		# Only enable scrolling if content is larger than view
		if ratio > 1.0:
			h_scrollbar.max_value = ratio
			h_scrollbar.page = 1.0 / ratio
			h_scrollbar.visible = true
		else:
			h_scrollbar.max_value = 1.0
			h_scrollbar.value = 0.0
			h_scrollbar.visible = false

func clear_tree() -> void:
	root_node = null
	current_nodes.clear()
	node_positions.clear()
	layout_dirty = true
	current_depth = 0
	visible_nodes.clear()
	current_path_nodes.clear()
	node_map.clear()
	performance_stats = {
		"nodes_explored": 0,
		"nodes_pruned": 0,
		"calculation_time": 0.0,
		"max_depth": 0
	}
	queue_redraw()

# Get a hash for the board to uniquely identify nodes
func _get_board_hash(board: Array) -> String:
	var hash_str = ""
	for col in board:
		for cell in col:
			hash_str += str(cell)
	return hash_str

# Adds node to the map for faster lookups
func _add_to_node_map(node: TreeNode) -> void:
	node.board_hash = _get_board_hash(node.board)
	node_map[node.board_hash] = node

func add_or_update_node(board: Array, score: float, move: Vector2i, is_maximizing: bool, depth: int, is_pruned: bool = false) -> void:
	if is_calculating and not show_calculation:
		# Store updates for later if we're not showing intermediate calculations
		pending_updates.append({
			"board": board.duplicate(true),
			"score": score,
			"move": move,
			"is_maximizing": is_maximizing,
			"depth": depth,
			"is_pruned": is_pruned
		})
		return
	
	_apply_node_update(board, score, move, is_maximizing, depth, is_pruned)

func _apply_node_update(board: Array, score: float, move: Vector2i, is_maximizing: bool, depth: int, is_pruned: bool = false) -> void:
	var calculation_time = Time.get_ticks_msec() / 1000.0 - last_calculation_time
	performance_stats.max_depth = max(performance_stats.max_depth, depth)
	
	if root_node == null:
		# Create root node
		root_node = TreeNode.new(board, score, move, is_maximizing, depth, is_pruned)
		root_node.calculation_time = calculation_time
		_add_to_node_map(root_node)
		current_nodes = [root_node]
		layout_dirty = true
		print("Created root node at depth", depth)
		call_deferred("queue_redraw")
		return
	
	# Find parent node based on board state and move
	var parent_node = _find_parent_node(board, move)
	if parent_node == null:
		# If no direct parent found, try to find most appropriate based on depth
		var potential_parents = current_nodes.filter(func(node): return node.depth == depth - 1)
		if potential_parents.size() > 0:
			parent_node = potential_parents[potential_parents.size() - 1]
		else:
			# Fallback to root if no better match
			parent_node = root_node
	
	# Check if node already exists
	var exists = false
	for child in parent_node.children:
		if child.move == move:
			# Update existing node
			child.score = score
			child.is_pruned = is_pruned
			child.calculation_time = calculation_time
			exists = true
			break
	
	if not exists:
		# Create new node and link to parent
		var new_node = TreeNode.new(board, score, move, is_maximizing, depth, is_pruned)
		new_node.parent = parent_node
		new_node.calculation_time = calculation_time
		parent_node.children.append(new_node)
		_add_to_node_map(new_node)
		
		# Track current nodes at each depth level for pruning visualization
		while current_nodes.size() > 0 and current_nodes[0].depth < depth:
			current_nodes.pop_front()
		
		# Add this new node to current nodes
		current_nodes.append(new_node)
	
	# Keep track of maximum depth
	current_depth = max(current_depth, depth)
	
	layout_dirty = true
	call_deferred("queue_redraw")

# Find parent node based on board state and move
func _find_parent_node(board: Array, move: Vector2i) -> TreeNode:
	if not root_node or move.x < 0:
		return null
	
	# Try to find previous board state
	var previous_board = _get_previous_board_state(board, move)
	if previous_board:
		var key = _get_board_hash(previous_board)
		if key in node_map:
			return node_map[key]
	
	# If exact match not found, use BFS to find potential parent
	if root_node:
		var queue = [root_node]
		while queue.size() > 0:
			var node = queue.pop_front()
			
			if _is_potential_parent(node.board, board, move):
				return node
			
			queue.append_array(node.children)
	
	return null

func _is_potential_parent(parent_board: Array, child_board: Array, move: Vector2i) -> bool:
	# Check if parent_board can become child_board by making a move
	var diff_count = 0
	var diff_col = -1
	var _diff_row = -1
	
	for c in range(min(parent_board.size(), child_board.size())):
		for r in range(min(parent_board[c].size(), child_board[c].size())):
			if parent_board[c][r] != child_board[c][r]:
				diff_count += 1
				diff_col = c
				_diff_row = r
	
	# If difference is one chip and it's in specified column, this is a potential parent
	return diff_count == 1 and diff_col == move.x

func _get_previous_board_state(board: Array, move: Vector2i) -> Array:
	if move.x < 0 or move.x >= board.size():
		return []
	
	var previous_board = []
	for c in range(board.size()):
		previous_board.append(board[c].duplicate())
	
	# Find the last placed chip in column and set to empty
	var found = false
	for r in range(previous_board[move.x].size() - 1, -1, -1):
		if previous_board[move.x][r] != 0:  # Assuming 0 is empty
			previous_board[move.x][r] = 0
			found = true
			break
	
	return previous_board if found else []

func calculate_layout() -> void:
	if not root_node:
		print("No root node to calculate layout for")
		return
	
	node_positions.clear()
	layout_width = 0
	layout_height = 0
	
	# Use a recursive approach to determine positions
	_calculate_node_positions(root_node, 0, 0)
	
	# Add some space below the deepest node
	layout_height = (current_depth + 1) * vertical_spacing + node_size.y
	
	# Update visible nodes list
	_update_visible_nodes()
	
	layout_dirty = false
	update_scrollbars()

func _calculate_node_positions(node: TreeNode, depth: int, order: int) -> int:
	if depth > max_visible_depth and not node.is_current_path:
		return order
	
	if node.is_pruned and not show_pruned_nodes:
		return order
	
	var _total_width = 0
	var child_count = 0
	
	# First calculate positions for all children
	for child in node.children:
		if (show_pruned_nodes or not child.is_pruned) or child.is_current_path:
			order = _calculate_node_positions(child, depth + 1, order)
			child_count += 1
	
	# Position this node based on its children or as a leaf
	var pos_x = 0.0
	if child_count > 0:
		# Position based on children's average x position
		var sum_x = 0.0
		var visible_children = 0
		for child in node.children:
			if node_positions.has(child) and (show_pruned_nodes or not child.is_pruned or child.is_current_path):
				sum_x += node_positions[child].x
				visible_children += 1
		
		if visible_children > 0:
			pos_x = sum_x / visible_children
		else:
			pos_x = order * horizontal_spacing
			order += 1
	else:
		# Leaf node
		pos_x = order * horizontal_spacing
		order += 1
	
	# Store position
	node_positions[node] = Vector2(pos_x, depth * vertical_spacing)
	
	# Update maximum width
	layout_width = max(layout_width, pos_x + node_size.x)
	
	return order

# Update the list of visible nodes for performance
func _update_visible_nodes() -> void:
	visible_nodes.clear()
	if not root_node:
		return
		
	var nodes_to_check = [root_node]
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		
		# Check if node is within view and matches display criteria
		if node_positions.has(node) and (show_pruned_nodes or not node.is_pruned or node.is_current_path):
			visible_nodes.append(node)
		
		# Add children if within max depth or if they're part of current path
		if node.depth < max_visible_depth or node.is_current_path:
			for child in node.children:
				if show_pruned_nodes or not child.is_pruned or child.is_current_path:
					nodes_to_check.append(child)

func _draw() -> void:
	if not root_node:
		draw_absent_graph_message()
		return
	
	if layout_dirty:
		calculate_layout()
	
	# Draw connections first (so they appear behind nodes)
	_draw_connections()
	
	# Draw nodes
	_draw_nodes()
	
	# Draw tooltip if node is hovered
	if hovered_node:
		_draw_tooltip(hovered_node)
	
	# Call draw performance stats
	performance_stats_updated.emit(performance_stats)

func draw_absent_graph_message() -> void:
	var message = "Waiting for AI player to calculate moves..."
	var font_size = 18
	var text_size = tooltip_font.get_string_size(message, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = size / 2 - text_size / 2
	draw_string(tooltip_font, text_pos, message, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func _draw_connections() -> void:
	for node in visible_nodes:
		for child in node.children:
			if node_positions.has(child) and (show_pruned_nodes or not child.is_pruned or child.is_current_path):
				var start_pos = node_positions[node] + node_size / 2
				var end_pos = node_positions[child] + node_size / 2
				
				start_pos = start_pos + pan_offset
				end_pos = end_pos + pan_offset
				
				# Determine line color based on node states
				var connection_color = line_color
				if node.is_current_path and child.is_current_path:
					connection_color = current_path_color
					draw_line(start_pos, end_pos, connection_color, line_width * 2)
				elif child.is_pruned:
					connection_color = pruned_color
					draw_line(start_pos, end_pos, connection_color, line_width)
				else:
					draw_line(start_pos, end_pos, connection_color, line_width)

func _draw_nodes() -> void:
	for node in visible_nodes:
		if node_positions.has(node):
			var pos = node_positions[node] + pan_offset
			var rect_size = node_size
			
			# Determine node color
			var node_color = _get_node_color(node)
			
			# Draw node circle
			var radius = min(rect_size.x, rect_size.y) / 2
			draw_circle(pos + rect_size/2, radius, node_color)
			
			# Draw outline for hovered node
			if node == hovered_node:
				draw_circle(pos + rect_size/2, radius + 2, Color.WHITE)
				draw_circle(pos + rect_size/2, radius, node_color)
			
			# Draw move column (as number)
			if node.move.x >= 0:
				var col_text = str(node.move.x)
				var col_text_size = node_font.get_string_size(col_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
				draw_string(node_font, 
					pos + Vector2(rect_size.x/2 - col_text_size.x/2, rect_size.y/2 + col_text_size.y/2 - 2), 
					col_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, text_color)
			
			# Draw score if enabled
			if show_values:
				var score_text = "%.1f" % node.score
				if abs(node.score) > 5000:  # Likely a win/lose score
					score_text = "W" if node.score > 0 else "L"
					
				var score_text_size = node_font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
				var score_pos = pos + Vector2(rect_size.x/2 - score_text_size.x/2, rect_size.y + score_text_size.y + 5)
				draw_string(node_font, score_pos, score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.LIGHT_GRAY)

func _get_node_color(node: TreeNode) -> Color:
	if node.is_pruned:
		return pruned_color
	elif node.is_current_path:
		return current_path_color
	elif node.is_maximizing:
		return maximizer_color
	else:
		return minimizer_color

func _draw_tooltip(node: TreeNode) -> void:
	var text = node.get_tooltip_text()
	var lines = text.split("\n")
	var max_line_width = 0
	var total_height = 0
	
	for line in lines:
		var line_size = tooltip_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size)
		max_line_width = max(max_line_width, line_size.x)
		total_height += line_size.y
	
	max_line_width += tooltip_padding.x * 2
	total_height += tooltip_padding.y * 2
	
	var node_pos = (node_positions[node] + node_size/2) + pan_offset
	var tooltip_pos = node_pos + Vector2(node_size.x / 2 + 5, -total_height / 2)
	
	# Adjust tooltip position to stay within view rect
	if tooltip_pos.x + max_line_width > size.x:
		tooltip_pos.x = node_pos.x - max_line_width - node_size.x / 2 - 5
	if tooltip_pos.y < 0:
		tooltip_pos.y = 0
	if tooltip_pos.y + total_height > size.y:
		tooltip_pos.y = size.y - total_height
	
	var tooltip_rect = Rect2(tooltip_pos, Vector2(max_line_width, total_height))
	draw_rect(tooltip_rect, tooltip_background_color)
	draw_rect(tooltip_rect, tooltip_text_color, false)
	
	var y_offset = tooltip_padding.y
	for line in lines:
		draw_string(tooltip_font, tooltip_pos + Vector2(tooltip_padding.x, y_offset + tooltip_font_size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size, tooltip_text_color)
		y_offset += tooltip_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size).y

func reset_view() -> void:
	pan_offset = Vector2(50, 50)  # Initial padding
	queue_redraw()
	
	# Reset scrollbars
	var v_scrollbar = find_gui_element("VScrollBar")
	if v_scrollbar:
		v_scrollbar.value = 0.0
		
	var h_scrollbar = find_gui_element("HScrollBar")
	if h_scrollbar:
		h_scrollbar.value = 0.0

# Update current best path for visualization
func update_best_path(best_move: int = -1) -> void:
	_reset_current_path()
	
	if not root_node or best_move < 0:
		return
	
	# Find the child node corresponding to best move
	for child in root_node.children:
		if child.move.x == best_move:
			var current = child
			# Trace path from this node
			while current != null:
				current.is_current_path = true
				current_path_nodes.append(current)
				
				# Find best child to continue path
				if current.children.size() > 0:
					var best_child = current.children[0]
					for child_node in current.children:
						if current.is_maximizing and child_node.score > best_child.score:
							best_child = child_node
						elif not current.is_maximizing and child_node.score < best_child.score:
							best_child = child_node
					current = best_child
				else:
					current = null
			break
	
	layout_dirty = true
	queue_redraw()

func _reset_current_path() -> void:
	for node in current_path_nodes:
		node.is_current_path = false
	current_path_nodes.clear()

# Calculate total nodes after calculation
func update_stats() -> void:
	if not root_node:
		return
		
	var total_nodes = _count_total_nodes(root_node)
	var pruned_nodes = _count_pruned_nodes(root_node)
	performance_stats.nodes_explored = total_nodes
	performance_stats.nodes_pruned = pruned_nodes

func _count_total_nodes(start_node: TreeNode) -> int:
	var count = 0
	var visited = {}
	var stack = [start_node]
	
	while stack.size() > 0:
		var node = stack.pop_back()
		if node.board_hash in visited:
			continue
			
		visited[node.board_hash] = true
		count += 1
		
		for child in node.children:
			if not child.board_hash in visited:
				stack.push_back(child)
				
	return count

func _count_pruned_nodes(start_node: TreeNode) -> int:
	var count = 0
	var visited = {}
	var stack = [start_node]
	
	while stack.size() > 0:
		var node = stack.pop_back()
		if node.board_hash in visited:
			continue
			
		visited[node.board_hash] = true
		if node.is_pruned:
			count += 1
		
		for child in node.children:
			if not child.board_hash in visited:
				stack.push_back(child)
				
	return count

func _on_calculation_started() -> void:
	clear_tree()
	last_calculation_time = Time.get_ticks_msec() / 1000.0
	reset_view()
	
	# Ensure visibility
	modulate.a = 1.0
	visible = true

func _on_minimax_calculated(board: Array, score: float, move: Vector2i, is_maximizing: bool, depth: int, is_pruned: bool = false) -> void:
	add_or_update_node(board, score, move, is_maximizing, depth, is_pruned)

func _on_move_calculated(best_move: int = -1) -> void:
	# Update performance stats
	performance_stats.calculation_time = Time.get_ticks_msec() / 1000.0 - last_calculation_time
	update_stats()
	
	# Update best path visualization
	update_best_path(best_move)
	
	# Sort nodes at each level by their col value (move.x)
	if root_node:
		_sort_nodes_by_col(root_node)
		layout_dirty = true
	
	print("Move calculation complete in %.3fs" % performance_stats.calculation_time)
	queue_redraw()

# Sort nodes by col value recursively
func _sort_nodes_by_col(node: TreeNode) -> void:
	# Sort children by col value (move.x)
	node.children.sort_custom(func(a, b): return a.move.x < b.move.x)
	
	# Recursively sort all children
	for child in node.children:
		_sort_nodes_by_col(child)

func _input(event: InputEvent) -> void:
	if not is_visible() or size.x <= 0 or size.y <= 0:
		return
	
	if event is InputEventMouseButton:
		if get_rect().has_point(event.position):
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					dragging = true
					drag_start = event.position
				else:
					dragging = false
	
	elif event is InputEventMouseMotion:
		if dragging:
			pan_offset += event.position - drag_start
			drag_start = event.position
			# Update scrollbar values to reflect manual panning
			var v_scrollbar = find_gui_element("VScrollBar")
			if v_scrollbar and v_scrollbar.max_value > 1.0:
				v_scrollbar.value = -pan_offset.y
			var h_scrollbar = find_gui_element("HScrollBar")
			if h_scrollbar and h_scrollbar.max_value > 1.0:
				h_scrollbar.value = -(pan_offset.x - 50)
		# Обработка наведения для отображения tooltip
		hovered_node = null
		for node in visible_nodes:
			if node_positions.has(node):
				var pos = node_positions[node] + pan_offset
				var rect_size = node_size
				# Определяем центр узла и радиус (узел рисуется как окружность)
				var center = pos + rect_size / 2
				var radius = min(rect_size.x, rect_size.y) / 2
				if event.position.distance_to(center) <= radius:
					hovered_node = node
					break
		queue_redraw()
