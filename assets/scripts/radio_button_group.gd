extends Node

var button_group_instance = ButtonGroup.new()

func _ready() -> void:
	for child in get_children():
		if child is BaseButton:
			child.button_group = button_group_instance
