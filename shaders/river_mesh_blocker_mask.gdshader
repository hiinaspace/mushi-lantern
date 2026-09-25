shader_type spatial;
render_mode blend_add, depth_draw_never, unshaded, cull_disabled;
stencil_mode write, compare_always, 1;

uniform bool debug_mask = false;

void fragment() {
	// A transparent overlay depth-tests against its original opaque mesh,
	// marking only visible shrine/staff pixels before the tube is drawn.
	ALBEDO = debug_mask ? vec3(0.85, 0.02, 0.02) : vec3(0.0);
	ALPHA = debug_mask ? 0.65 : 0.001;
}
