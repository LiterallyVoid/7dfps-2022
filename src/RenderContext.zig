const std = @import("std");

const linalg = @import("./linalg.zig");

matrix_projection: linalg.Mat4,

matrix_camera_to_world: linalg.Mat4,
matrix_world_to_camera: linalg.Mat4,
