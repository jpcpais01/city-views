class_name TriBudget
extends RefCounted
## Counts every triangle the scene can draw (shadow casters twice, as the
## shadow pass redraws them) so tests can hold the frame under budget.

const BUDGET := 200000


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
