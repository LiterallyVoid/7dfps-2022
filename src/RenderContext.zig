const std = @import("std");

const linalg = @import("./linalg.zig");
const Texture = @import("./Texture.zig");

aspect: f32,

matrix_projection: linalg.Mat4,

matrix_camera_to_world: linalg.Mat4,
matrix_world_to_camera: linalg.Mat4,

texture_shadow: Texture,
matrix_shadow: linalg.Mat4,

pub fn camera_position(self: @This()) linalg.Vec3 {
    return self.matrix_camera_to_world.multiplyVector(linalg.Vec4.new(0.0, 0.0, 0.0, 1.0)).xyz();
}

pub fn camera_direction(self: @This()) linalg.Vec3 {
    return self.matrix_camera_to_world.multiplyVector(linalg.Vec4.new(0.0, 0.0, -1.0, 0.0)).xyz();
}
