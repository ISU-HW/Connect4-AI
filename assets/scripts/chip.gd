extends RigidBody3D

@export var board_position: Vector2i
@export var bounce_sound: AudioStreamPlayer
var previous_velocity_y: float = 0.0

func setup(config: SpawnConfig):
#region Root Rotation
	self.global_rotation_degrees = Vector3(0, 0, randi_range(0, 360))
#endregion
#region Model Color
	var model_color = config.model_color
	var mesh = $Chip
	var material = mesh.get_active_material(0).duplicate()
	if material is StandardMaterial3D or material is ORMMaterial3D:
		material.albedo_color = model_color
	elif material is ShaderMaterial:
		material.set_shader_parameter('albedo', model_color)
	for n in mesh.get_surface_override_material_count():
		mesh.set_surface_override_material(n, material)
#endregion	

func _ready():
	connect4.win.connect(_on_connect4_win)
	#for node in get_tree().get_nodes_in_group("Pieces"):
		#var _audio_player = node.get_node_or_null("AudioStreamPlayer")
		#if audio_player is AudioStreamPlayer:
			#audio_player.stream_paused = true
	self.add_to_group("Pieces")
	
	#var timer = get_tree().create_timer(5.0, false, true)
	#timer.timeout.connect(
		#func():
			#print("Timeout!")
	#)
	#await get_tree().create_timer(0.1).timeout
	#while timer.get_time_left() != 0.0:
		#await get_tree().physics_frame
		#if snapped(self.linear_velocity.y, 0.001) == 0.0:
			#break
	#self.freeze = true
	#print("Freeze!")

func _physics_process(_delta):
	var current_velocity_y = linear_velocity.y
	if previous_velocity_y < 0 and current_velocity_y > 0:
		if bounce_sound and not bounce_sound.playing:
			bounce_sound.play()
	previous_velocity_y = current_velocity_y

func _on_connect4_win():
	if board_position in connect4.win_chips:
		await get_tree().create_timer(1).timeout
		$win.visible = true
		$Chip.scale.y *= 2
