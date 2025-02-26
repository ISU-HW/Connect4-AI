shader_type spatial;
render_mode unshaded;

// Цвет основного объекта
uniform vec4 base_color: source_color = vec4(1.0);
// Цвет обводки
uniform vec4 outline_color: source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Толщина обводки
uniform float outline_width: hint_range(0.001, 0.1) = 0.02;
// Граница чувствительности глубины
uniform float depth_threshold: hint_range(0.0, 1.0) = 0.01;

uniform sampler2D SCREEN_TEXTURE:hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec2 texel_size = vec2(1.0) / vec2(textureSize(SCREEN_TEXTURE, 0));
    float depth = texture(SCREEN_TEXTURE, SCREEN_UV).r;
    
    bool edge_detected = false;
    
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            
            float sample_depth = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(float(x), float(y)) * texel_size * outline_width).r;
            
            if (abs(depth - sample_depth) > depth_threshold) {
                edge_detected = true;
            }
        }
    }
    
    if (edge_detected) {
        ALBEDO = outline_color.rgb;
        ALPHA = outline_color.a;
    } else {
        ALBEDO = base_color.rgb;
        ALPHA = base_color.a;
    }
}