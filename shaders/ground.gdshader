shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// the island ground: city shading plus world-space colour drift and fine grain,
// so meadows, sand and rock read as one landscape instead of tile squares
#define GROUND
#include "res://shaders/city.gdshaderinc"
