class_name Palette
extends RefCounted
## The town's shared colours, and the plain material shadow stand-ins draw with.

const BRICK := [Color("c2684f"), Color("b55d4a"), Color("d48a6a"), Color("e8d2b0"), Color("a8b8c8")]
const AWNINGS := [Color("e85d5d"), Color("3fae8c"), Color("4b86d6"), Color("f2b33d"), Color("ef7fa8"), Color("8a6fd6")]
const GLASS := Color(0.32, 0.47, 0.6)
const GLASS_LIGHT := Color(0.55, 0.72, 0.84)
const ASPHALT := Color(0.36, 0.38, 0.43)
const SIDEWALK := Color(0.88, 0.85, 0.8)
const LEAF := [Color("6fb35a"), Color("5ea552"), Color("82c063"), Color("4e9a54"), Color("97c45a")]
const BLOSSOM := [Color("f4a7c0"), Color("f7c2d4"), Color("ee8fb0"), Color("fbe3ea")]
const LAUNDRY := [Color("ffffff"), Color("7fb8e6"), Color("ef7f6a"), Color("f2c14e"), Color("f4a7c0"), Color("3fae8c")]
const FLOWERS := [Color("ef5b5b"), Color("f2c14e"), Color("ffffff"), Color("8a6fd6"), Color("ef7fa8"), Color("4b86d6"), Color("f28b3c")]

static var _shadow_mat: Material


## Double-sided, so stand-in winding never matters in the shadow pass.
static func shadow_material() -> Material:
	if _shadow_mat == null:
		var m := StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat = m
	return _shadow_mat
