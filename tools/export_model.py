# -*- tab-width: 4; indent-tabs-mode: t; python-indent-offset: 4 -*-

import bmesh, struct, bpy

depsgraph = bpy.context.evaluated_depsgraph_get()

def reevaluate_depsgraph():
	global depsgraph
	depsgraph = bpy.context.evaluated_depsgraph_get()

vertices = []
vertex_indices = {}
materials = {}

armatures = set()

for object in depsgraph.objects:
	if object.type == 'ARMATURE':
		armatures.add(object.original)

all_bones = {}

def bone_matrix(key):
	obj_name, bone_name = key

	obj = depsgraph.objects[obj_name]
	bone = obj.pose.bones[bone_name]

	return obj.matrix_world @ bone.matrix

def write_matrix(mat):
	return struct.pack('<16f', *(el for row in mat for el in row))

def bone_info(obj, name):
	key = (obj.name, name)
	if key in all_bones:
		return all_bones[key]

	parent = obj.pose.bones[name].parent

	if parent is not None:
		parent = bone_info(obj, parent.name)

	rest = bone_matrix(key)
	rest_inverted = rest.inverted()

	all_bones[key] = {
		"key": key,
		"index": len(all_bones),
		"rest": rest,
		"rest_local": rest if parent is None else rest @ parent["rest_inverted"],
		"rest_inverted": rest_inverted,
		"parent": parent,
		"frames": [],
	}

	return all_bones[key]

def vertex_to_index(position, normal, uv, bone_indices, bone_weights):
	data = struct.pack(
		"<3f3bx2f4B4B",
		*position,
		*(int(e * 127) for e in normal),
		*uv,
		*bone_indices,
		*(int(e * 255) for e in bone_weights),
	)
	if data in vertex_indices:
		return vertex_indices[data]

	vertices.append(data)
	vertex_indices[data] = len(vertices) - 1

	return len(vertices) - 1

def export_mesh(obj):
	print(f"Exporting mesh \"{obj.name}\"...")

	mesh_obj = obj.evaluated_get(depsgraph)
	mesh = mesh_obj.to_mesh()

	bm = bmesh.new()
	bm.from_mesh(mesh)
	bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='FIXED', ngon_method='EAR_CLIP')
	bm.to_mesh(mesh)
	bm.free()

	mesh.transform(obj.matrix_world)

	mesh.calc_normals_split()

	uvmap = mesh.uv_layers.active

	vertices = []

	bones = []
	for group in mesh_obj.vertex_groups:
		info = bone_info(mesh_obj.parent, group.name)
		bones.append([info["index"], group])

	for poly in mesh.polygons:
		mat_name = mesh_obj.material_slots[poly.material_index].material.name
		try:
			material = materials[mat_name]
		except:
			material = []
			materials[mat_name] = material
		for poly_vert_index in range(3):
			vert_index = poly.vertices[poly_vert_index]
			loop_index = poly.loop_indices[poly_vert_index]

			vert = mesh.vertices[vert_index]
			loop = mesh.loops[loop_index]

			all_bones = [(0, 0)] * 4
			for bone in bones:
				try:
					all_bones.append([bone[0], bone[1].weight(vert_index)])
				except:
					pass

			all_bones = list(sorted(all_bones, key = lambda a: -a[1]))[0:4]

			bone_indices = [g[0] for g in all_bones]
			bone_weights = [g[1] for g in all_bones]

			idx = vertex_to_index(vert.co, loop.normal, uvmap.data[loop_index].uv, bone_indices, bone_weights)
			material.append(idx)

	mesh_obj.to_mesh_clear()

all_bone_data = []

#for armature in armatures:
#	armature.data.pose_position = 'REST'
bpy.context.scene.frame_current = 0

reevaluate_depsgraph()

#frames = range(bpy.context.scene.frame_start, bpy.context.scene.frame_end + 1)
frames = range(0, bpy.context.scene.frame_end + 1)

bones = []

for object in depsgraph.objects:
	if object.type == 'MESH':
		export_mesh(object)

for armature in armatures:
	armature.data.pose_position = 'POSE'

for frame in frames:
	bpy.context.scene.frame_current = frame
	reevaluate_depsgraph()

	for key in all_bones:
		info = all_bones[key]

		matrix = bone_matrix(key).copy()

		if info["parent"] is not None:
			parent = (info["rest_local"] @ bone_matrix(info["parent"]["key"])).inverted()
		else:
			parent = info["rest_local"].inverted()

		matrix = parent @ matrix

		info["frames"].append(matrix)

assert bpy.data.filepath.endswith(".blend")
f = open(bpy.data.filepath[0:-len(".blend")] + ".model", "wb")

f.write(struct.pack("<IIIII", len(materials), len(all_bones), len(frames), sum(len(m) for m in materials.values()), len(vertices)))

indices = []

for m in materials:
	name = m.encode("utf-8")
	f.write(struct.pack("<I", len(name)))
	f.write(name)

	f.write(struct.pack("<II", len(indices), len(materials[m])))

	indices += materials[m]

for key, bone in all_bones.items():
	name = (key[0] + "/" + key[1]).encode("utf-8")

	parent = bone["parent"]
	parent_idx = parent["index"] if parent is not None else -1
	f.write(struct.pack("<iI", parent_idx, len(name)))
	f.write(name)

	f.write(write_matrix(bone["rest_local"]))
	f.write(write_matrix(bone["rest_inverted"]))

for bone in all_bones.values():
	for frame_index, frame in enumerate(frames):
		f.write(write_matrix(bone["frames"][frame_index]))

for index in indices:
	f.write(struct.pack("<I", index))

f.write(b"".join(vertices))

f.close()
