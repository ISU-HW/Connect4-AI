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
		board = b.duplicate(true) if b.size() > 0 else []
		score = s
		move = m
		is_maximizing = max_player
		depth = d
		is_pruned = pruned
		node_id = id if id != "" else str(randi())
		board_hash = _calculate_board_hash()

	func _calculate_board_hash() -> String:
		if board.is_empty():
			return ""
		var hash_str = ""
		for col in board:
			for cell in col:
				hash_str += str(cell)
		return hash_str

	func get_tooltip_text() -> String:
		var text = ""
		text += "Оценка: %.2f" % score
		text += "\nХод: Колонка %d" % move.x if move.x >= 0 else "\nХод: Корень"
		text += "\nГлубина: %d" % depth
		text += "\nИгрок: %s" % ("МАКС" if is_maximizing else "МИН")
		text += "\nОтсечен: %s" % ("Да" if is_pruned else "Нет")
		text += "\nАльфа: %.2f" % alpha
		text += "\nБета: %.2f" % beta
		text += "\nДетей: %d" % children.size()
		text += "\nID узла: %s" % node_id
		return text

# Основные переменные
var root_node: TreeNode = null
var visible_nodes: Array[TreeNode] = []
var current_path_nodes: Array[TreeNode] = []
var hovered_node: TreeNode = null

var node_map: Dictionary = {}
var id_node_map: Dictionary = {}
var node_positions: Dictionary = {}

# Настройки отображения
var node_size: Vector2 = Vector2(20, 20)
var horizontal_spacing: float = 40.0
var vertical_spacing: float = 60.0
var line_width: float = 2.0
var show_pruned_nodes: bool = true
var show_values: bool = true
var show_calculation: bool = false

# Цвета
var maximizer_color: Color = Color(0.2, 0.8, 0.2)
var minimizer_color: Color = Color(0.8, 0.2, 0.2)
var pruned_color: Color = Color(0.6, 0.6, 0.6, 0.8)
var current_path_color: Color = Color(1.0, 0.8, 0.2)
var text_color: Color = Color.WHITE
var line_color: Color = Color(0.5, 0.5, 0.5)

# Навигация
var pan_offset: Vector2 = Vector2(50, 50)
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

# Макет
var layout_dirty: bool = true
var layout_width: float = 0.0
var layout_height: float = 0.0

# Статистика
var performance_stats: Dictionary = {
	"nodes_explored": 0,
	"nodes_pruned": 0,
	"calculation_time": 0.0,
	"max_depth": 0,
	"total_nodes": 0
}

# Шрифты
var node_font: Font
var tooltip_font: Font
var tooltip_font_size: int = 14
var tooltip_background_color: Color = Color(0.0, 0.0, 0.0, 0.9)
var tooltip_text_color: Color = Color.WHITE
var tooltip_padding: Vector2 = Vector2(10, 8)

# Состояние
var is_calculating: bool = false

func _ready() -> void:
	node_font = ThemeDB.fallback_font
	tooltip_font = ThemeDB.fallback_font
	
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	if connect4 and connect4.ai_player:
		connect4.ai_player.tree_updated.connect(_on_tree_updated)
		connect4.ai_player.move_calculation_started.connect(_on_calculation_started)
	
	performance_stats_updated.emit(performance_stats)
	
	modulate.a = 1.0
	visible = true

# ==================== ОБРАБОТКА СИГНАЛОВ ОТ AI ====================

func _on_tree_updated(tree_data: Dictionary, current_path: Array) -> void:
	is_calculating = true
	
	if root_node == null:
		clear_tree()
		_build_tree_from_dict(tree_data)
	else:
		_update_tree_from_dict(tree_data)
	
	_highlight_current_path(current_path)
	_update_stats()
	layout_dirty = true
	queue_redraw()
	
	if tree_data.get("calculation_time", 0.0) > 0:
		is_calculating = false
		performance_stats.calculation_time = tree_data.get("calculation_time", 0.0)

func _on_calculation_started() -> void:
	print("Начато вычисление хода AI...")
	clear_tree()
	_reset_view()
	is_calculating = true

# ==================== ПОСТРОЕНИЕ ДЕРЕВА ====================

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

	if node.board_hash != "":
		node_map[node.board_hash] = node
	id_node_map[node.node_id] = node

	for child_dict in tree_dict.get("children", []):
		var child_node = _build_tree_from_dict(child_dict)
		if child_node:
			child_node.parent = node
			node.children.append(child_node)

	return node

func _update_tree_from_dict(tree_dict: Dictionary) -> void:
	if root_node != null and tree_dict.get("id", "") == root_node.node_id:
		_update_node_from_dict(root_node, tree_dict)
	
	_update_children_from_dict(root_node, tree_dict.get("children", []))

func _update_node_from_dict(node: TreeNode, node_dict: Dictionary) -> void:
	node.score = node_dict.get("score", node.score)
	node.alpha = node_dict.get("alpha", node.alpha)
	node.beta = node_dict.get("beta", node.beta)
	node.is_pruned = node_dict.get("is_pruned", node.is_pruned)
	node.calculation_time = node_dict.get("calculation_time", node.calculation_time)

func _update_children_from_dict(parent_node: TreeNode, children_data: Array) -> void:
	if not parent_node:
		return
		
	for child_dict in children_data:
		var node_id = child_dict.get("id", "")
		if node_id == "":
			continue
			
		var node = id_node_map.get(node_id)

		if node != null:
			_update_node_from_dict(node, child_dict)
			_update_children_from_dict(node, child_dict.get("children", []))
		else:
			var new_node = TreeNode.new(
				child_dict.get("board", []),
				child_dict.get("score", 0.0),
				child_dict.get("move", Vector2i(-1, -1)),
				child_dict.get("is_maximizing", true),
				child_dict.get("depth", 0),
				child_dict.get("is_pruned", false),
				node_id
			)

			_update_node_from_dict(new_node, child_dict)
			new_node.parent = parent_node
			parent_node.children.append(new_node)
			
			if new_node.board_hash != "":
				node_map[new_node.board_hash] = new_node
			id_node_map[new_node.node_id] = new_node

			_update_children_from_dict(new_node, child_dict.get("children", []))

# ==================== ВЫДЕЛЕНИЕ ПУТЕЙ ====================

func _highlight_current_path(path_ids: Array) -> void:
	for node in current_path_nodes:
		node.is_current_path = false
	current_path_nodes.clear()

	if path_ids.is_empty() or not root_node:
		return

	for node_id in path_ids:
		if node_id in id_node_map:
			var node = id_node_map[node_id]
			node.is_current_path = true
			current_path_nodes.append(node)

# ==================== РАСЧЕТ МАКЕТА ====================

func calculate_layout() -> void:
	if not root_node:
		return

	node_positions.clear()
	layout_width = 0
	layout_height = 0

	_calculate_node_positions(root_node, 0, 0)
	
	layout_height = (_get_max_depth() + 1) * vertical_spacing + node_size.y
	_update_visible_nodes()
	
	layout_dirty = false

func _calculate_node_positions(node: TreeNode, depth: int, order: int) -> int:
	if node.is_pruned and not show_pruned_nodes and not node.is_current_path:
		return order

	var child_positions = []
	var sorted_children = node.children.duplicate()
	sorted_children.sort_custom(func(a, b):
		return a.move.x < b.move.x
	)

	for child in sorted_children:
		if (not child.is_pruned or show_pruned_nodes or child.is_current_path):
			order = _calculate_node_positions(child, depth + 1, order)
			if node_positions.has(child):
				child_positions.append(node_positions[child].x)

	var pos_x = 0.0
	if child_positions.size() > 0:
		var sum_x = 0.0
		for x in child_positions:
			sum_x += x
		pos_x = sum_x / child_positions.size()
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
	
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		if node_positions.has(node):
			if (not node.is_pruned or show_pruned_nodes or node.is_current_path):
				visible_nodes.append(node)
		for child in node.children:
			nodes_to_check.append(child)

# ==================== ОТРИСОВКА ====================

func _draw() -> void:
	if not root_node:
		_draw_waiting_message()
		return

	if layout_dirty:
		calculate_layout()

	_draw_connections()
	_draw_nodes()
	
	if hovered_node:
		_draw_tooltip(hovered_node)
	
	performance_stats_updated.emit(performance_stats)

func _draw_waiting_message() -> void:
	var message = "Ожидание вычислений ИИ..."
	if is_calculating:
		message = "Вычисляется дерево решений..."
	
	var font_size = 18
	var text_size = tooltip_font.get_string_size(message, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = size / 2 - text_size / 2
	draw_string(tooltip_font, text_pos, message, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.LIGHT_GRAY)

func _draw_connections() -> void:
	for node in visible_nodes:
		for child in node.children:
			if not node_positions.has(child):
				continue
			if child.is_pruned and not show_pruned_nodes and not child.is_current_path:
				continue
				
			var start_pos = node_positions[node] + node_size / 2 + pan_offset
			var end_pos = node_positions[child] + node_size / 2 + pan_offset
			
			var connection_color = line_color
			var line_thickness = line_width
			
			if node.is_current_path and child.is_current_path:
				connection_color = current_path_color
				line_thickness *= 2
			elif child.is_pruned:
				connection_color = pruned_color
				line_thickness *= 0.7
			
			draw_line(start_pos, end_pos, connection_color, line_thickness)

func _draw_nodes() -> void:
	for node in visible_nodes:
		if not node_positions.has(node):
			continue
			
		var pos = node_positions[node] + pan_offset
		var radius = min(node_size.x, node_size.y) / 2
		var center = pos + node_size / 2

		var node_color = _get_node_color(node)
		draw_circle(center, radius, node_color)
		
		if node == hovered_node:
			draw_circle(center, radius + 2, Color.WHITE, false, 2)
		
		_draw_node_text(node, pos)

func _draw_node_text(node: TreeNode, pos: Vector2) -> void:
	var font_size = 14
	var center = pos + node_size / 2
	
	if node.move.x >= 0:
		var col_text = str(node.move.x + 1)
		var col_text_size = node_font.get_string_size(col_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var col_pos = center - col_text_size / 2
		draw_string(node_font, col_pos, col_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

	if show_values:
		var y_offset = node_size.y + 5
		var score_text = "%.1f" % node.score
		if abs(node.score) >= 5000:
			score_text = "ПБД" if node.score > 0 else "ПРЖ"
		
		var score_size = node_font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var score_pos = Vector2(center.x - score_size.x/2, pos.y + y_offset)
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
		total_height += line_size.y + 2

	var tooltip_size = Vector2(max_line_width + tooltip_padding.x * 2, total_height + tooltip_padding.y * 2)
	var node_pos = (node_positions[node] + node_size/2) + pan_offset
	var tooltip_pos = node_pos + Vector2(node_size.x / 2 + 10, -tooltip_size.y / 2)

	if tooltip_pos.x + tooltip_size.x > size.x:
		tooltip_pos.x = node_pos.x - tooltip_size.x - node_size.x / 2 - 10
	if tooltip_pos.y < 0:
		tooltip_pos.y = 5
	if tooltip_pos.y + tooltip_size.y > size.y:
		tooltip_pos.y = size.y - tooltip_size.y - 5

	var tooltip_rect = Rect2(tooltip_pos, tooltip_size)
	draw_rect(tooltip_rect, tooltip_background_color)
	draw_rect(tooltip_rect, Color.WHITE, false, 1)

	var y_offset = tooltip_padding.y + tooltip_font_size
	for line in lines:
		draw_string(tooltip_font, tooltip_pos + Vector2(tooltip_padding.x, y_offset), line, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size, tooltip_text_color)
		y_offset += tooltip_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size).y + 2

# ==================== ОБРАБОТКА ВВОДА ====================

func _input(event: InputEvent) -> void:
	if not is_visible() or size.x <= 0 or size.y <= 0:
		return

	var global_mouse_pos = get_global_mouse_position()
	var local_pos = global_mouse_pos - global_position
	
	if not get_rect().has_point(local_pos):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_start = local_pos
			else:
				dragging = false
	elif event is InputEventMouseMotion:
		if dragging:
			var delta = local_pos - drag_start
			pan_offset += delta
			drag_start = local_pos
			queue_redraw()
		else:
			var old_hovered = hovered_node
			hovered_node = _get_node_at_position(local_pos)
			if old_hovered != hovered_node:
				queue_redraw()

func _get_node_at_position(pos: Vector2) -> TreeNode:
	for node in visible_nodes:
		if not node_positions.has(node):
			continue
		var node_pos = node_positions[node] + pan_offset
		var center = node_pos + node_size / 2
		var radius = min(node_size.x, node_size.y) / 2
		if pos.distance_to(center) <= radius:
			return node
	return null

# ==================== УТИЛИТЫ ====================

func _reset_view() -> void:
	pan_offset = Vector2(50, 50)
	layout_dirty = true
	queue_redraw()

func _get_max_depth() -> int:
	if not root_node:
		return 0
	return _get_node_max_depth(root_node)

func _get_node_max_depth(node: TreeNode) -> int:
	var max_depth = node.depth
	for child in node.children:
		max_depth = max(max_depth, _get_node_max_depth(child))
	return max_depth

func _update_stats() -> void:
	if not root_node:
		return
	var stats = _count_nodes_recursive(root_node)
	performance_stats.nodes_explored = stats.total - stats.pruned
	performance_stats.nodes_pruned = stats.pruned
	performance_stats.total_nodes = stats.total
	performance_stats.max_depth = _get_max_depth()

func _count_nodes_recursive(node: TreeNode) -> Dictionary:
	var stats = {"total": 1, "pruned": 0}
	if node.is_pruned:
		stats.pruned = 1
	for child in node.children:
		var child_stats = _count_nodes_recursive(child)
		stats.total += child_stats.total
		stats.pruned += child_stats.pruned
	return stats

func clear_tree() -> void:
	root_node = null
	visible_nodes.clear()
	current_path_nodes.clear()
	hovered_node = null
	
	node_positions.clear()
	node_map.clear()
	id_node_map.clear()
	
	layout_dirty = true
	layout_width = 0.0
	layout_height = 0.0
	
	performance_stats = {
		"nodes_explored": 0,
		"nodes_pruned": 0,
		"calculation_time": 0.0,
		"max_depth": 0,
		"total_nodes": 0
	}
	
	queue_redraw()
