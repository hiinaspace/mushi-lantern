shader_type spatial;
render_mode blend_add, depth_draw_never, unshaded, cull_disabled;
stencil_mode write, compare_always, 1;

uniform sampler2D fern_alpha : filter_linear_mipmap, repeat_disable;

void fragment() {
	if (texture(fern_alpha, UV).r < 0.48) {
		discard;
	}
	ALPHA = 0.001;
}
