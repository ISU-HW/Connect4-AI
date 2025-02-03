class_name SpawnPoint
extends Marker3D

@export var variants: Array[SpawnConfig] = []

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
	
	instance.set_as_top_level(true)
	instance.visible = false
	
	# Рассчитываем позицию спавна относительно текущего объекта
	var spawn_transform = global_transform.translated(offset)
	
	parent.add_child(instance)
	instance.global_transform = spawn_transform
	
	# Отложенное обновление видимости для предотвращения графических артефактов
	instance.set_deferred("visible", true)
	
	if instance.has_method("setup"):
		instance.setup(variant_config)
	else:
		push_warning("Объект %s не имеет метода setup()" % instance.name)
	
	instance.tree_entered.connect(_on_variant_spawned.bind(instance))
	
	return instance


func _on_variant_spawned(instance: Node) -> void:
	# Сброс физических параметров для RigidBody
	if instance is RigidBody3D:
		instance.linear_velocity = Vector3.ZERO
		instance.angular_velocity = Vector3.ZERO
	
	instance.force_update_transform()
	print("Создан объект %s на позиции: %s" % [instance.name, instance.global_position])
