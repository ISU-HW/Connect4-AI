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
	var is_current_path: bool = false
	var children: Array[TreeNode] = []
	var parent: TreeNode = null
	var alpha: float = -INF
	var beta: float = INF
	var calculation_time: float = 0.0
	var board_hash: String = ""
	var node_id: String = ""

	func _init(b: Array, s: float, m: Vector2i, max_player: bool, d: int, pruned: bool = false, id: String = ""):
		board = b.duplicate(true)
		score = s
		move = m
		is_maximizing = max_player
		depth = d
		is_pruned = pruned
		node_id = id
		board_hash = _calculate_board_hash()

	func _calculate_board_hash() -> String:
		var hash_str = ""
		for col in board:
			for cell in col:
				hash_str += str(cell)
		return hash_str

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
		text += "\nNode ID: %s" % node_id
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

var layout_dirty: bool = true
var node_positions: Dictionary = {}
var layout_width: float = 0.0
var layout_height: float = 0.0
var pan_offset: Vector2 = Vector2(50, 50)
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

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
var id_node_map = {}
var is_calculating: bool = false

func _ready() -> void:
	node_font = ThemeDB.fallback_font
	tooltip_font = ThemeDB.fallback_font
	set_process_input(true)

	performance_stats_updated.emit(performance_stats)

	connect4.ai_player.tree_updated.connect(_on_tree_updated)
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

	modulate.a = 1.0
	visible = true

func _on_tree_updated(tree_data: Dictionary, current_path: Array) -> void:
	is_calculating = true

	if root_node == null:
		last_calculation_time = Time.get_ticks_msec() / 1000.0
		clear_tree()
		_build_tree_from_dict(tree_data)
	else:
		_update_tree_from_dict(tree_data)

	_highlight_current_path(current_path)
	update_stats()

	layout_dirty = true
	queue_redraw()

	if tree_data.get("calculation_time", 0.0) > 0:
		is_calculating = false
		performance_stats.calculation_time = tree_data.get("calculation_time", 0.0)

		var best_move = -1
		for child in root_node.children:
			if child.score > best_move:
				best_move = child.move.x

		update_best_path(best_move)

func _build_tree_from_dict(tree_dict: Dictionary) -> TreeNode:
	if tree_dict.is_empty():
		return null

	var node = TreeNode.new(
		tree_dict.get("board", []),
		tree_dict.get("score", 0.0),
		tree_dict.get("move", Vector2i(-1, -1)),
		tree_dict.get("is_maximizing", true),
		tree_dict.get("depth", 0),
		tree_dict.get("is_pruned", false),
		tree_dict.get("id", "")
	)

	node.alpha = tree_dict.get("alpha", -INF)
	node.beta = tree_dict.get("beta", INF)
	node.calculation_time = tree_dict.get("calculation_time", 0.0)

	if root_node == null:
		root_node = node

	node_map[node.board_hash] = node
	id_node_map[node.node_id] = node

	for child_dict in tree_dict.get("children", []):
		var child_node = _build_tree_from_dict(child_dict)
		if child_node:
			child_node.parent = node
			node.children.append(child_node)

	return node

func _update_tree_from_dict(tree_dict: Dictionary) -> void:
	# First, update root node properties
	if root_node != null and tree_dict.get("id", "") == root_node.node_id:
		root_node.score = tree_dict.get("score", root_node.score)
		root_node.alpha = tree_dict.get("alpha", root_node.alpha)
		root_node.beta = tree_dict.get("beta", root_node.beta)
		root_node.is_pruned = tree_dict.get("is_pruned", root_node.is_pruned)
		root_node.calculation_time = tree_dict.get("calculation_time", root_node.calculation_time)

	# Then recursively update or add children
	_update_children_from_dict(root_node, tree_dict.get("children", []))

func _update_children_from_dict(parent_node: TreeNode, children_data: Array) -> void:
	for child_dict in children_data:
		var node_id = child_dict.get("id", "")
		var node = id_node_map.get(node_id)

		if node != null:
			# Update existing node
			node.score = child_dict.get("score", node.score)
			node.alpha = child_dict.get("alpha", node.alpha)
			node.beta = child_dict.get("beta", node.beta)
			node.is_pruned = child_dict.get("is_pruned", node.is_pruned)
			node.calculation_time = child_dict.get("calculation_time", node.calculation_time)

			# Update its children
			_update_children_from_dict(node, child_dict.get("children", []))
		else:
			# Add new node as child
			var new_node = TreeNode.new(
				child_dict.get("board", []),
				child_dict.get("score", 0.0),
				child_dict.get("move", Vector2i(-1, -1)),
				child_dict.get("is_maximizing", true),
				child_dict.get("depth", 0),
				child_dict.get("is_pruned", false),
				child_dict.get("id", "")
			)

			new_node.alpha = child_dict.get("alpha", -INF)
			new_node.beta = child_dict.get("beta", INF)
			new_node.calculation_time = child_dict.get("calculation_time", 0.0)
			new_node.parent = parent_node

			parent_node.children.append(new_node)
			node_map[new_node.board_hash] = new_node
			id_node_map[new_node.node_id] = new_node

			# Process children recursively
			_update_children_from_dict(new_node, child_dict.get("children", []))

func _highlight_current_path(path_ids: Array) -> void:
	_reset_current_path()

	if path_ids.is_empty() or not root_node:
		return

	for node_id in path_ids:
		if node_id in id_node_map:
			var node = id_node_map[node_id]
			node.is_current_path = true
			current_path_nodes.append(node)

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
	queue_redraw()

func _on_v_scrollbar_value_changed(value: float) -> void:
	var v_scroll_offset = value * size.y
	pan_offset.y = -v_scroll_offset
	queue_redraw()

func _on_h_scrollbar_value_changed(value: float) -> void:
	var h_scroll_offset = value * size.x
	pan_offset.x = -h_scroll_offset + 50
	queue_redraw()

func update_scrollbars() -> void:
	update_vertical_scrollbar()
	update_horizontal_scrollbar()

func update_vertical_scrollbar() -> void:
	var v_scrollbar = find_gui_element("VScrollBar")
	if v_scrollbar:
		var view_height = size.y

		var ratio = layout_height / view_height

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

		var ratio = layout_width / view_width

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
	id_node_map.clear()
	performance_stats = {
		"nodes_explored": 0,
		"nodes_pruned": 0,
		"calculation_time": 0.0,
		"max_depth": 0
	}
	queue_redraw()

func calculate_layout() -> void:
	if not root_node:
		print("No root node to calculate layout for")
		return

	node_positions.clear()
	layout_width = 0
	layout_height = 0

	_calculate_node_positions(root_node, 0, 0)

	layout_height = (current_depth + 1) * vertical_spacing + node_size.y

	_update_visible_nodes()

	layout_dirty = false
	update_scrollbars()

func _calculate_node_positions(node: TreeNode, depth: int, order: int) -> int:
	if depth > max_visible_depth and not node.is_current_path:
		return order

	if node.is_pruned and not show_pruned_nodes and not node.is_current_path:
		return order

	var child_count = 0

	for child in node.children:
		if (show_pruned_nodes or not child.is_pruned) or child.is_current_path:
			order = _calculate_node_positions(child, depth + 1, order)
			child_count += 1

	var pos_x = 0.0
	if child_count > 0:
		var sum_x = 0.0
		var visible_children = 0
		for child in node.children:
			if node_positions.has(child) and ((show_pruned_nodes or not child.is_pruned) or child.is_current_path):
				sum_x += node_positions[child].x
				visible_children += 1

		if visible_children > 0:
			pos_x = sum_x / visible_children
		else:
			pos_x = order * horizontal_spacing
			order += 1
	else:
		pos_x = order * horizontal_spacing
		order += 1

	node_positions[node] = Vector2(pos_x, depth * vertical_spacing)

	layout_width = max(layout_width, pos_x + node_size.x)

	return order

func _update_visible_nodes() -> void:
	visible_nodes.clear()
	if not root_node:
		return

	var nodes_to_check = [root_node]
	performance_stats.max_depth = 0

	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()

		# Update max depth statistics
		performance_stats.max_depth = max(performance_stats.max_depth, node.depth)

		if node_positions.has(node) and ((show_pruned_nodes or not node.is_pruned) or node.is_current_path):
			visible_nodes.append(node)

		if node.depth < max_visible_depth or node.is_current_path or show_calculation:
			for child in node.children:
				if (show_pruned_nodes or not child.is_pruned or child.is_current_path) or show_calculation:
					nodes_to_check.append(child)

func _draw() -> void:
	if not root_node:
		draw_absent_graph_message()
		return

	if layout_dirty:
		calculate_layout()

	_draw_connections()

	_draw_nodes()

	if hovered_node:
		_draw_tooltip(hovered_node)

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
			if node_positions.has(child) and ((show_pruned_nodes or not child.is_pruned) or child.is_current_path):
				var start_pos = node_positions[node] + node_size / 2
				var end_pos = node_positions[child] + node_size / 2

				start_pos = start_pos + pan_offset
				end_pos = end_pos + pan_offset

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

			var node_color = _get_node_color(node)

			var radius = min(rect_size.x, rect_size.y) / 2
			draw_circle(pos + rect_size/2, radius, node_color)

			if node == hovered_node:
				draw_circle(pos + rect_size/2, radius + 2, Color.WHITE)
				draw_circle(pos + rect_size/2, radius, node_color)

			if node.move.x >= 0:
				var col_text = str(node.move.x)
				var col_text_size = node_font.get_string_size(col_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
				draw_string(node_font,
					pos + Vector2(rect_size.x/2 - col_text_size.x/2, rect_size.y/2 + col_text_size.y/2 - 2),
					col_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, text_color)

			if show_values:
				var score_text = "%.1f" % node.score
				if abs(node.score) > 5000:
					score_text = "W" if node.score > 0 else "L"

				var score_text_size = node_font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
				var score_pos = pos + Vector2(rect_size.x/2 - score_text_size.x/2, rect_size.y + score_text_size.y + 5)
				draw_string(node_font, score_pos, score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.LIGHT_GRAY)

func _get_node_color(node: TreeNode) -> Color:
	if node.is_current_path:
		return current_path_color
	elif node.is_pruned:
		return pruned_color
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
	pan_offset = Vector2(50, 50)
	queue_redraw()

	var v_scrollbar = find_gui_element("VScrollBar")
	if v_scrollbar:
		v_scrollbar.value = 0.0

	var h_scrollbar = find_gui_element("HScrollBar")
	if h_scrollbar:
		h_scrollbar.value = 0.0

func update_best_path(best_move: int = -1) -> void:
	_reset_current_path()

	if not root_node or best_move < 0:
		return

	for child in root_node.children:
		if child.move.x == best_move:
			var current = child
			while current != null:
				current.is_current_path = true
				current_path_nodes.append(current)

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

func update_stats() -> void:
	if not root_node:
		return

	var stats = _count_nodes(root_node)
	performance_stats.nodes_explored = stats.total
	performance_stats.nodes_pruned = stats.pruned

func _count_nodes(start_node: TreeNode) -> Dictionary:
	var stats = {"total": 0, "pruned": 0}
	var visited = {}
	var stack = [start_node]

	while stack.size() > 0:
		var node = stack.pop_back()
		if node.node_id in visited:
			continue

		visited[node.node_id] = true
		stats.total += 1

		if node.is_pruned:
			stats.pruned += 1

		for child in node.children:
			if not child.node_id in visited:
				stack.push_back(child)

	return stats

func _on_calculation_started() -> void:
	clear_tree()
	last_calculation_time = Time.get_ticks_msec() / 1000.0
	reset_view()
	is_calculating = true

	modulate.a = 1.0
	visible = true

func _on_move_calculated(best_move: int = -1) -> void:
	is_calculating = false
	update_stats()
	update_best_path(best_move)

	if root_node:
		_sort_nodes_by_col(root_node)
		layout_dirty = true

	queue_redraw()

func _sort_nodes_by_col(node: TreeNode) -> void:
	node.children.sort_custom(func(a, b): return a.move.x < b.move.x)

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
			var v_scrollbar = find_gui_element("VScrollBar")
			if v_scrollbar and v_scrollbar.max_value > 1.0:
				v_scrollbar.value = -pan_offset.y
			var h_scrollbar = find_gui_element("HScrollBar")
			if h_scrollbar and h_scrollbar.max_value > 1.0:
				h_scrollbar.value = -(pan_offset.x - 50)
		hovered_node = null
		for node in visible_nodes:
			if node_positions.has(node):
				var pos = node_positions[node] + pan_offset
				var rect_size = node_size
				var center = pos + rect_size / 2
				var radius = min(rect_size.x, rect_size.y) / 2
				if event.position.distance_to(center) <= radius:
					hovered_node = node
					break
		queue_redraw()
