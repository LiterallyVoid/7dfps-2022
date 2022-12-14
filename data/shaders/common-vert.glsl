#ifdef SKELETAL

uniform mat4 u_projection;
uniform mat4 u_world_to_camera;
uniform mat4 u_model_to_world;
uniform mat4 u_bones[64];

void add_bone_matrix(inout mat4 matrix, inout float total_weight, int index, float weight) {
	matrix += u_bones[index] * weight;
	total_weight += weight;
}

mat4 get_bones_matrix() {
	mat4 matrix_bones = mat4(0.001);
	float total_weight = 0.001;

	add_bone_matrix(matrix_bones, total_weight, a_bone_indices.x, a_bone_weights.x);
	add_bone_matrix(matrix_bones, total_weight, a_bone_indices.y, a_bone_weights.y);
	add_bone_matrix(matrix_bones, total_weight, a_bone_indices.z, a_bone_weights.z);
	add_bone_matrix(matrix_bones, total_weight, a_bone_indices.w, a_bone_weights.w);

	return matrix_bones / total_weight;
}

#endif
