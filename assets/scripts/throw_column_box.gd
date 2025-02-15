extends MeshInstance3D

@export var tween_duration: float = 0.2
@export var shake_offset: float = 0.1
@export_enum("X", "Y", "Z") var shake_axis: String = "X"

var material = get_surface_override_material(0)
var highlight_tween: Tween
var shake_tween: Tween
var original_position: Vector3
var original_color: Color

func _ready() -> void:
	connect4.not_valid_move.connect(_not_valid)
	original_position = position
	if material:
		original_color = material.albedo_color

func _not_valid():
	_shake()
	highlight_with_color(Color.RED)

func highlight_with_color(color: Color):
	if not material:
		return
		
	if highlight_tween and highlight_tween.is_valid():
		highlight_tween.kill()
	
	# Save original alpha
	var target_color = color
	target_color.a = material.albedo_color.a
	
	highlight_tween = create_tween()
	highlight_tween.tween_property(material, "albedo_color", target_color, tween_duration)
	highlight_tween.tween_property(material, "albedo_color", original_color, tween_duration)

func _shake():
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()
		
	shake_tween = create_tween()
	
	# Create directional vector based on selected axis
	var direction = Vector3.ZERO
	match shake_axis:
		"X": direction.x = 1.0
		"Y": direction.y = 1.0
		"Z": direction.z = 1.0
	
	# Apply shake_offset to the direction vector
	var offset = direction * shake_offset
	
	# Quick shake sequence
	shake_tween.tween_property(self, "position", original_position + offset, tween_duration/4)
	shake_tween.tween_property(self, "position", original_position - offset, tween_duration/4)
	shake_tween.tween_property(self, "position", original_position + offset * 0.5, tween_duration/4)
	shake_tween.tween_property(self, "position", original_position, tween_duration/4)
