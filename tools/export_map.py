# -*- tab-width: 4; indent-tabs-mode: t; python-indent-offset: 4 -*-

import bmesh, struct, bpy

depsgraph = bpy.context.evaluated_depsgraph_get()

vertices = []
vertex_indices = {}
materials = {}

def vertex_to_index(position, normal, tangent, bitangent, uv):
	data = struct.pack("<3f3b3b3b2f", *position, *(int(e * 127) for e in normal), *(int(e * 127) for e in tangent), *(int(e * 127) for e in bitangent), *uv)
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

	mesh.calc_tangents(uvmap = uvmap.name)

	vertices = []

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

			idx = vertex_to_index(vert.co, loop.normal, loop.tangent, loop.bitangent, uvmap.data[loop_index].uv)
			material.append(idx)

	mesh_obj.to_mesh_clear()

for object in depsgraph.objects:
	if object.type == 'MESH':
		export_mesh(object)

assert bpy.data.filepath.endswith(".blend")
f = open(bpy.data.filepath[0:-len(".blend")] + ".map", "wb")

entities = []

for obj in depsgraph.objects:
        if obj.type == 'EMPTY':
                kind = 0
                if 'gunner' in obj.name:
                        kind = 1
                if 'coin' in obj.name:
                        kind = 2
                if 'player' in obj.name:
                        kind = 3
                entities.append(struct.pack("<Iffff", kind, *obj.location, obj.rotation_euler.z))

f.write(struct.pack("<IIII", len(materials), len(entities), sum(len(m) for m in materials.values()), len(vertices)))

indices = []

for m in materials:
	name = m.encode("utf-8")
	f.write(struct.pack("<I", len(name)))
	f.write(name)

	f.write(struct.pack("<II", len(indices), len(materials[m])))

	indices += materials[m]

for index in indices:
	f.write(struct.pack("<I", index))

f.write(b"".join(vertices))

f.write(b"".join(entities))

f.close()
