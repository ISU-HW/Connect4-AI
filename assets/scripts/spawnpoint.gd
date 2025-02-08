class_name SpawnPoint
extends Marker3D

@export var variants: Array[SpawnConfig] = []
var last_spawned_instance

func get_variants():
	return variants

func spawn_by_index_variants(index: int, offset: Vector3 = Vector3()) -> Node:
	if variants.is_empty():
		push_warning("Нет доступных вариантов для спавна")
		return null
	
	if index < 0 or index >= variants.size():
		push_error("Некорректный индекс варианта: %d (всего вариантов: %d)" % [index, variants.size()])
		return null
	
	var parent := get_parent()
	if not parent:
		push_error("Невозможно создать объект - узел не имеет родителя")
		return null
	
	var variant_config = variants[index]
	var instance = variant_config.scene.instantiate()
	
	instance.board_position = connect4.last_move
	instance.set_as_top_level(true)
	instance.visible = false
	
	var spawn_transform = global_transform.translated(offset)
	
	parent.add_child(instance)
	instance.global_transform = spawn_transform
	instance.set_deferred("visible", true)
	
	if instance.has_method("setup"):
		instance.setup(variant_config)
	else:
		push_warning("Объект %s не имеет метода setup()" % instance.name)
		
	return instance
