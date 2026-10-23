shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// flush details (windows, paint): city shading plus window rows, which cut
// their gaps with discard, so it is kept off the solid geometry's shader
#define WINDOW_ROWS
#include "res://shaders/city.gdshaderinc"
