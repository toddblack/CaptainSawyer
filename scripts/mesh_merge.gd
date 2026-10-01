class_name MeshMerge
extends RefCounted

## Bakes every MeshInstance3D under `parts` (with its node transforms, relative
## to the instantiated GLB `root`) into ONE ArrayMesh with one surface per
## material.  Claude Design GLBs ship as dozens to hundreds of pieces; merged
## they're one draw call per material.
static func merge(root: Node, parts: Array[Node]) -> ArrayMesh:
	# Material -> SurfaceTool collecting every piece that uses it.
	var by_mat: Dictionary = {}
	for part: Node in parts:
		var pieces: Array[Node] = part.find_children("*", "MeshInstance3D", true, false)
		if part is MeshInstance3D:
			pieces.append(part)
		for node: Node in pieces:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf: Transform3D = Transform3D.IDENTITY
			var n: Node = mi
			while n != root and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			if root is Node3D:
				xf = (root as Node3D).transform * xf
			for s: int in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_active_material(s)
				if not by_mat.has(mat):
					var st_new: SurfaceTool = SurfaceTool.new()
					st_new.begin(Mesh.PRIMITIVE_TRIANGLES)
					by_mat[mat] = st_new
				(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, xf)

	var merged: ArrayMesh = ArrayMesh.new()
	for mat: Variant in by_mat.keys():
		var st: SurfaceTool = by_mat[mat] as SurfaceTool
		if mat != null:
			st.set_material(mat as Material)
		st.commit(merged)
	return merged
