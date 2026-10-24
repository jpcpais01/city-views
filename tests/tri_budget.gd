class_name TriBudget
extends RefCounted
## Counts every triangle the scene can draw (shadow casters twice, as the
## shadow pass redraws them) so tests can hold the frame under budget.

const BUDGET := 200000
## all the way out, past CameraRig.FAR_D, a little more is allowed (João, 2026-10-24)
const FAR_BUDGET := 240000
## tilted right up to look across the town from the side (João, 2026-10-24)
const SIDE_BUDGET := 260000


static func count(root: Node) -> Dictionary:
	var acc := {}
	_walk(root, acc, "")
	return acc


static func total(acc: Dictionary) -> int:
	var t := 0
	for k in acc:
		t += acc[k][0] + acc[k][1]
	return t


static func _walk(n: Node, acc: Dictionary, group: String) -> void:
	for c in n.get_children():
		var g := group
		if g == "" or n is World:
			g = _label(c)
		if c is GeometryInstance3D and (c as Node3D).is_visible_in_tree():
			var mesh: Mesh = null
			var copies := 1
			if c is MeshInstance3D:
				mesh = c.mesh
			elif c is MultiMeshInstance3D and c.multimesh:
				mesh = c.multimesh.mesh
				copies = c.multimesh.visible_instance_count if c.multimesh.visible_instance_count >= 0 else c.multimesh.instance_count
			if mesh:
				var t := tris(mesh) * copies
				var sh: bool = c.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if not acc.has(g):
					acc[g] = [0, 0]
				if c.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
					acc[g][0] += t
				if sh:
					acc[g][1] += t
		_walk(c, acc, g)


static func tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null and idx.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t


static func _label(c: Node) -> String:
	var sc: Script = c.get_script()
	if sc and sc.get_global_name() != "":
		return sc.get_global_name()
	if c.has_meta("batch"):
		return "batch%d" % c.get_meta("batch")
	if c is MeshInstance3D and c.mesh:
		return "%s/%s" % [c.get_class(), c.mesh.get_class()]
	return c.get_class()


## Like count(), but only what a camera at `eye` looking at `at` (vertical
## field of view `fov`, 16:9) can see: the map is bigger than one view, and the
## frame only ever draws what is in it. Shadow casters are counted when they
## stand in view too.
static func count_view(root: Node, eye: Vector3, at: Vector3, fov := 40.0, far := 1100.0) -> Dictionary:
	var fwd := (at - eye).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var tv := tan(deg_to_rad(fov * 0.5))
	var th := tv * 16.0 / 9.0
	var planes := []
	for edge: Array in [[right * th, up], [-right * th, up], [up * tv, right], [-up * tv, right]]:
		var dirn: Vector3 = fwd + edge[0]
		var nrm: Vector3 = dirn.cross(edge[1]).normalized()
		var pl := Plane(nrm, eye)
		# normals point out of the view
		if pl.distance_to(eye + fwd) > 0.0:
			pl = Plane(-nrm, eye)
		planes.append(pl)
	planes.append(Plane(-fwd, eye + fwd * 0.3))
	planes.append(Plane(fwd, eye + fwd * far))
	var acc := {}
	_walk_view(root, acc, "", planes)
	return acc


static func _walk_view(n: Node, acc: Dictionary, group: String, planes: Array) -> void:
	for c in n.get_children():
		var g := group
		if g == "" or n is World:
			g = _label(c)
		if c is GeometryInstance3D and (c as Node3D).is_visible_in_tree():
			var mesh: Mesh = null
			var copies := 1
			if c is MeshInstance3D:
				mesh = c.mesh
			elif c is MultiMeshInstance3D and c.multimesh:
				mesh = c.multimesh.mesh
				copies = c.multimesh.visible_instance_count if c.multimesh.visible_instance_count >= 0 else c.multimesh.instance_count
			if mesh and (c is MultiMeshInstance3D or _in_view((c as Node3D).global_transform * mesh.get_aabb(), planes)):
				var t := tris(mesh) * copies
				if not acc.has(g):
					acc[g] = [0, 0]
				if c.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
					acc[g][0] += t
				if c.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					acc[g][1] += t
		_walk_view(c, acc, g, planes)


static func _in_view(box: AABB, planes: Array) -> bool:
	for pl: Plane in planes:
		# the box corner furthest along the plane's inward side
		var p := box.position
		if pl.normal.x < 0.0: p.x += box.size.x
		if pl.normal.y < 0.0: p.y += box.size.y
		if pl.normal.z < 0.0: p.z += box.size.z
		if pl.distance_to(p) > 0.0:
			return false
	return true
