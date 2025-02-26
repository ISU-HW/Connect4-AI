shader_type spatial;
render_mode unshaded, cull_front;

// Настройки обводки
uniform vec4 outline_color: source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness: hint_range(0.0, 0.1) = 0.02;

void vertex() {
    // Смещаем вершины вдоль нормалей
    VERTEX += NORMAL * outline_thickness;
}

void fragment() {
    // Просто возвращаем цвет обводки
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}