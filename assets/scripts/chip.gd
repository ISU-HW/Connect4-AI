extends RigidBody3D

@export var board_position: Vector2i
@export var bounce_sound: AudioStreamPlayer

var previous_velocity_y: float = 0.0
var _prevent_bounce_sound: bool = false
var _is_highlight_particle_prevented: bool = false

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
	connect4.chip_dropped.connect(_on_new_chip_dropped)
	body_entered.connect(_on_body_entered)
	add_to_group("pieces")
	
	var timer = get_tree().create_timer(3.0, false, true)
	
	await get_tree().create_timer(0.1).timeout
	while timer.get_time_left() != 0.0:
		await get_tree().physics_frame
		if snapped(self.linear_velocity.y, 0.001) == 0.0:
			break
	_prevent_bounce_sound = true
	
	if not _is_highlight_particle_prevented:
		%highlight_particle.visible = true
		await get_tree().create_timer(15.0).timeout
		%highlight_particle.visible = false

func _physics_process(_delta):
	var current_velocity_y = linear_velocity.y
	if previous_velocity_y < 0 and current_velocity_y > 0:
		if not _prevent_bounce_sound and not bounce_sound.playing:
			bounce_sound.play()
	previous_velocity_y = current_velocity_y

func _on_connect4_win():
	if board_position in connect4.win_chips:
		_is_highlight_particle_prevented = true
		await get_tree().create_timer(1.5).timeout
		%win_particle.visible = true
		%Chip.scale.y *= 2

func _on_new_chip_dropped(last_move, _current_player):
	if board_position != last_move or connect4.is_game_ended():
		_is_highlight_particle_prevented = true
		%highlight_particle.visible = false

func _on_body_entered(body: Node):
	if body is RigidBody3D:
		var my_y = global_position.y
		var other_y = body.global_position.y
		
		if my_y > other_y:
			var my_height = 2*%CollisionShape3D.shape.radius
			var overlap = abs(my_y - other_y)
			
			if overlap > (my_height * 0.5):
				var impulse_strength = 1.0
				self.apply_impulse(Vector3(0, 1, 0) * impulse_strength)
