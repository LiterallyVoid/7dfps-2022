const std = @import("std");

pub fn primitiveCast(comptime Dest: type, item: anytype) Dest {
    const Source = @TypeOf(item);
    return switch (@typeInfo(Dest)) {
        .Int, .ComptimeInt => switch (@typeInfo(Source)) {
            .Int, .ComptimeInt => @intCast(Dest, item),
            .Float => @floatToInt(Dest, item),
            else => @compileError("primitiveCast can only cast between floats and ints, " ++ @typeName(Dest) ++ " is not supported"),
        },
        .Float => switch (@typeInfo(Source)) {
            .Int, .ComptimeInt => @intToFloat(Dest, item),
            .Float => @floatCast(Dest, item),
            else => @compileError("primitiveCast can only cast between floats and ints, " ++ @typeName(Dest) ++ " is not supported"),
        },
        else => @compileError("primitiveCast can only cast between floats and ints, " ++ @typeName(Dest) ++ " is not supported"),
    };
}

pub fn Vector(comptime dim: comptime_int, comptime Element_: type, comptime mixin: anytype) type {
    return struct {
        const Self = @This();

        pub const Element = Element_;

        data: [dim]Element,

        pub usingnamespace if (dim == 1)
            struct {
                pub fn new(x: Element) Self {
                    return Self{ .data = [_]Element{x} };
                }
            }
        else
            struct {};

        pub usingnamespace if (dim == 2)
            struct {
                pub fn new(x: Element, y: Element) Self {
                    return Self{ .data = [_]Element{ x, y } };
                }
            }
        else
            struct {};

        pub usingnamespace if (dim == 3)
            struct {
                pub fn new(x: Element, y: Element, z: Element) Self {
                    return Self{ .data = [_]Element{ x, y, z } };
                }

                pub fn cross(a: Self, b: Self) Self {
                    return Self{
                        .data = .{
                            a.data[1] * b.data[2] - a.data[2] * b.data[1],
                            a.data[2] * b.data[0] - a.data[0] * b.data[2],
                            a.data[0] * b.data[1] - a.data[1] * b.data[0],
                        },
                    };
                }

                pub fn xyzw(self: Self, w: f32) Vec4 {
                    return Vec4{ .data = [_]Element{ self.data[0], self.data[1], self.data[2], w } };
                }
            }
        else
            struct {};

        pub usingnamespace if (dim == 4)
            struct {
                pub fn new(x: Element, y: Element, z: Element, w: Element) Self {
                    return Self{ .data = [_]Element{ x, y, z, w } };
                }

                pub fn xyz(self: Self) Vec3 {
                    return Vec3{ .data = [_]Element{ self.data[0], self.data[1], self.data[2] } };
                }
            }
        else
            struct {};

        pub usingnamespace if (mixin != null) mixin(@This()) else struct {};

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
            _ = fmt;
            _ = options;

            try std.fmt.format(out_stream, "(", .{});
            inline for (self.data) |elem, i| {
                if (i > 0) {
                    try std.fmt.format(out_stream, ", ", .{});
                }
                try std.fmt.format(out_stream, "{d}", .{elem});
            }
            try std.fmt.format(out_stream, ")", .{});
        }

        pub fn zero() Self {
            var self: Self = undefined;
            inline for (self.data) |*el| {
                el.* = 0.0;
            }
            return self;
        }

        pub fn broadcast(value: Element) Self {
            var self: Self = undefined;
            inline for (self.data) |*el| {
                el.* = value;
            }
            return self;
        }

        pub fn add(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = self.data[i] + other.data[i];
            }
            return result;
        }

        pub fn sub(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = self.data[i] - other.data[i];
            }
            return result;
        }

        pub fn mul(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = self.data[i] * other.data[i];
            }
            return result;
        }

        pub fn mulScalar(self: Self, other: Element) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = self.data[i] * other;
            }
            return result;
        }

        pub fn div(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = self.data[i] / other.data[i];
            }
            return result;
        }

        pub fn divScalar(self: Self, other: Element) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = self.data[i] / other;
            }
            return result;
        }

        pub fn divScalarFloor(self: Self, other: Element) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = @divFloor(self.data[i], other);
            }
            return result;
        }

        pub fn min(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = std.math.min(self.data[i], other.data[i]);
            }
            return result;
        }

        pub fn max(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = std.math.max(self.data[i], other.data[i]);
            }
            return result;
        }

        pub fn minScalar(self: Self, other: Element) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = std.math.min(self.data[i], other);
            }
            return result;
        }

        pub fn maxScalar(self: Self, other: Element) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = std.math.max(self.data[i], other);
            }
            return result;
        }

        pub fn abs(self: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = @fabs(self.data[i]);
            }
            return result;
        }


        pub fn dot(self: Self, other: Self) Element {
            var sum: Element = 0;
            inline for (self.data) |_, i| {
                sum += self.data[i] * other.data[i];
            }
            return sum;
        }

        pub fn dotPoint(self: Self, other: anytype) Element {
            var sum: Element = 0;
            inline for (other.data) |_, i| {
                sum += self.data[i] * other.data[i];
            }

            sum += self.data[3];

            return sum;
        }

        pub fn negate(self: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = -self.data[i];
            }
            return result;
        }

        pub fn floor(self: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = @floor(self.data[i]);
            }
            return result;
        }

        pub fn ceil(self: Self) Self {
            var result: Self = undefined;
            inline for (self.data) |_, i| {
                result.data[i] = @ceil(self.data[i]);
            }
            return result;
        }

        pub fn length(self: Self) Element {
            return std.math.sqrt(self.lengthSquared());
        }

        pub fn lengthSquared(self: Self) Element {
            return self.dot(self);
        }

        pub fn smallerThan(self: Self, cmp: Element) bool {
            return self.lengthSquared() < cmp * cmp;
        }

        pub fn normalized(self: Self) Self {
            var len = self.length();
            if (len == 0.0) {
                return Self.zero();
            }
            return self.divScalar(len);
        }

        pub fn reflect(self: Self, dir: Self) Self {
            return self.sub(dir.mulScalar(2 * self.dot(dir)));
        }

        pub fn mix(self: Self, other: Self, ratio: Element) Self {
            return self.mulScalar(1.0 - ratio).add(other.mulScalar(ratio));
        }

        pub fn fromArray(comptime T: type, arr: [dim]T) Self {
            var self: Self = undefined;
            inline for (arr) |elem, i| {
                self.data[i] = primitiveCast(Element, elem);
            }
            return self;
        }

        pub fn toArray(self: Self, comptime T: type) [dim]T {
            var array: [dim]T = undefined;
            inline for (self.data) |el, i| {
                array[i] = primitiveCast(T, el);
            }
            return array;
        }

        pub fn toVector(self: Self, comptime T: type) T {
            var new: T = undefined;
            inline for (self.data) |el, i| {
                new.data[i] = primitiveCast(T.Element, el);
            }
            return new;
        }

        pub fn swizzle(self: Self, comptime T: type, comptime s: []const u8) T {
            var other: T = undefined;
            inline for (s) |axis, i| {
                other.data[i] = switch (axis) {
                    'x' => self.data[0],
                    'y' => self.data[1],
                    'z' => self.data[2],
                    'w' => self.data[3],
                    '0' => 0,
                    '1' => 1,
                    else => unreachable,
                };
            }
        }

        pub fn restrict(self: @This(), axis: @This()) @This() {
            return axis.mulScalar(self.dot(axis));
        }
    };
}

pub fn Matrix(comptime dim: comptime_int, comptime Element: type, comptime Vec: type, comptime Self: type) type {
    return struct {
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
            _ = fmt;
            _ = options;

            try std.fmt.format(out_stream, "Matrix4{{", .{});
            inline for (self.data) |row| {
                try std.fmt.format(out_stream, " {{", .{});
                inline for (row) |elem| {
                    try std.fmt.format(out_stream, "{d}, ", .{elem});
                }
                try std.fmt.format(out_stream, "}},", .{});
            }
            try std.fmt.format(out_stream, " }}", .{});
        }

        pub fn zero() Self {
            var self: Self = undefined;
            comptime var i = 0;
            inline while (i < dim) : (i += 1) {
                comptime var j = 0;
                inline while (j < dim) : (j += 1) {
                    self.data[i][j] = 0.0;
                }
            }
            return self;
        }

        pub fn identity() Self {
            var self: Self = undefined;
            comptime var i = 0;
            inline while (i < dim) : (i += 1) {
                comptime var j = 0;
                inline while (j < dim) : (j += 1) {
                    self.data[i][j] = if (i == j) 1.0 else 0.0;
                }
            }
            return self;
        }

        pub fn multiply(a: Self, b: Self) Self {
            var out: Self = Self.zero();
            comptime var i = 0;
            inline while (i < dim) : (i += 1) {
                comptime var j = 0;
                inline while (j < dim) : (j += 1) {
                    comptime var k = 0;
                    inline while (k < dim) : (k += 1) {
                        out.data[i][j] += a.data[k][j] * b.data[i][k];
                    }
                }
            }
            return out;
        }

        pub fn multiplyRHS(a: Self, b: Self) Self {
            return multiply(b, a);
        }

        pub fn multiplyVector(self: Self, vec: Vec) Vec {
            var v = Vec.zero();
            inline for (v.data) |*el, i| {
                comptime var j = 0;
                inline while (j < dim) : (j += 1) {
                    el.* += self.data[j][i] * vec.data[j];
                }
            }
            return v;
        }

        pub fn multiplyVectorOpp(self: Self, vec: Vec) Vec {
            var v = Vec.zero();
            inline for (v.data) |*el, i| {
                comptime var j = 0;
                inline while (j < dim) : (j += 1) {
                    el.* += self.data[i][j] * vec.data[j];
                }
            }
            return v;
        }

        pub fn translation(x: Element, y: Element, z: Element) Self {
            var mat = Self.identity();
            mat.data[3][0] = x;
            mat.data[3][1] = y;
            mat.data[3][2] = z;
            return mat;
        }

        pub fn scale(val: Element) Self {
            var mat = Self.identity();
            comptime var i = 0;
            inline while (i < (dim - 1)) : (i += 1) {
                mat.data[i][i] = val;
            }
            return mat;
        }

        pub fn scaleVec(val: Vec3) Self {
            var mat = Self.identity();
            comptime var i = 0;
            inline while (i < (dim - 1)) : (i += 1) {
                mat.data[i][i] = val.data[i];
            }
            return mat;
        }

        // This only works for mat3 and mat4, but who cares?.
        pub fn rotation(axis: Vec3, radians: Element) Self {
            std.debug.assert(blk: {
                var len = axis.lengthSquared();
                break :blk len > 0.999 and len < 1.001;
            });

            var s = std.math.sin(radians);
            var c = std.math.cos(radians);

            var axis_sq = axis.mul(axis);

            var out = Self.identity();
            out.data[0][0] = c + (axis_sq.data[0] * (1 - c));
            out.data[1][0] = axis.data[0] * axis.data[1] * (1 - c) - axis.data[2] * s;
            out.data[2][0] = axis.data[0] * axis.data[1] * (1 - c) + axis.data[1] * s;

            out.data[0][1] = axis.data[1] * axis.data[0] * (1 - c) + axis.data[2] * s;
            out.data[1][1] = c + (axis_sq.data[1] * (1 - c));
            out.data[2][1] = axis.data[1] * axis.data[2] * (1 - c) - axis.data[0] * s;

            out.data[0][2] = axis.data[2] * axis.data[0] * (1 - c) - axis.data[1] * s;
            out.data[1][2] = axis.data[2] * axis.data[1] * (1 - c) + axis.data[0] * s;
            out.data[2][2] = c + (axis_sq.data[2] * (1 - c));
            return out;
        }

        pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Self {
            var forward = center.sub(eye).normalized();
            var side = forward.cross(up).normalized();
            var newUp = side.cross(forward);

            var mat = Self.identity();
            mat.data[0][0] = side.data[0];
            mat.data[1][0] = side.data[1];
            mat.data[2][0] = side.data[2];

            mat.data[0][1] = newUp.data[0];
            mat.data[1][1] = newUp.data[1];
            mat.data[2][1] = newUp.data[2];

            mat.data[0][2] = -forward.data[0];
            mat.data[1][2] = -forward.data[1];
            mat.data[2][2] = -forward.data[2];

            mat.data[3][0] = -side.dot(eye);
            mat.data[3][1] = -newUp.dot(eye);
            mat.data[3][2] = forward.dot(eye);
            return mat;
        }

        pub fn transpose(self: Self) Self {
            var mat = Self.zero();
            inline for (mat.data) |*row, x| {
                inline for (row) |*elem, y| {
                    elem.* = self.data[y][x];
                }
            }
            return mat;
        }

        pub fn toArray(self: Self, comptime T: type, comptime row_major: bool) [dim * dim]T {
            var array: [dim * dim]T = undefined;
            inline for (self.data) |row, i| {
                inline for (row) |el, j| {
                    const id = if (row_major) (i * dim + j) else (j * dim + i);
                    array[id] = primitiveCast(T, el);
                }
            }
            return array;
        }
    };
}

pub const Vec2 = Vector(2, f32, null);
pub const Vec3 = Vector(3, f32, null);
pub const Vec4 = Vector(4, f32, null);

pub const IVec2 = Vector(2, i32, null);
pub const IVec3 = Vector(3, i32, null);
pub const IVec4 = Vector(4, i32, null);

pub const Quaternion = struct {
    data: [4]f32,

    pub fn new(_x: f32, _y: f32, _z: f32, _w: f32) @This() {
        return @This(){ .data = [_]f32{ _x, _y, _z, _w } };
    }

    pub fn identity() @This() {
        return @This(){ .data = [_]f32{ 0, 0, 0, 1 } };
    }

    pub fn fromAngularVelocity(velocity: Vec3) @This() {
        var length = velocity.length() * 0.5;

        if (length <= 0.0) {
            return @This(){
                .data = .{
                    velocity.data[0] * 0.5,
                    velocity.data[1] * 0.5,
                    velocity.data[2] * 0.5,
                    1.0,
                },
            };
        }

        var half = velocity.mulScalar((std.math.sin(length) / length) * 0.5);

        return @This(){
            .data = .{
                half.data[0],
                half.data[1],
                half.data[2],
                std.math.cos(length),
            },
        };
    }

    pub fn axisAngle(axis: Vec3, angle: f32) @This() {
        var s = std.math.sin(angle * 0.5);
        var c = std.math.cos(angle * 0.5);
        var tmp = axis.mulScalar(s);
        return @This(){ .data = [_]f32{ tmp.data[0], tmp.data[1], tmp.data[2], c } };
    }

    pub fn mul(lhs: @This(), rhs: @This()) @This() {
        var lhs_3 = Vec3.new(lhs.data[0], lhs.data[1], lhs.data[2]);
        var rhs_3 = Vec3.new(rhs.data[0], rhs.data[1], rhs.data[2]);
        var tmp = lhs_3.cross(rhs_3);
        tmp = tmp.add(lhs_3.mulScalar(rhs.data[3]));
        tmp = tmp.add(rhs_3.mulScalar(lhs.data[3]));
        var w = (lhs.data[3] * rhs.data[3]) - lhs_3.dot(rhs_3);
        return @This(){ .data = [_]f32{ tmp.data[0], tmp.data[1], tmp.data[2], w } };
    }

    pub fn dot(self: @This(), other: @This()) f32 {
        return self.data[0] * other.data[0] + self.data[1] * other.data[1] + self.data[2] * other.data[2] + self.data[3] * other.data[3];
    }

    pub fn mulScalar(self: @This(), value: f32) @This() {
        return @This().new(self.data[0] * value, self.data[1] * value, self.data[2] * value, self.data[3] * value);
    }

    pub fn add(self: @This(), other: @This()) @This() {
        return @This().new(self.data[0] + other.data[0], self.data[1] + other.data[1], self.data[2] + other.data[2], self.data[3] + other.data[3]);
    }

    pub fn normalized(self: @This()) @This() {
        var fac = 1.0 / std.math.sqrt(self.dot(self));
        return self.mulScalar(fac);
    }

    pub fn slerp(self: @This(), other: @This(), t: f32) @This() {
        var self_n = self.normalized();
        var other_n = other.normalized();
        var dotprod = self_n.dot(other_n);

        if (dotprod < 0.0) {
            self_n = self.mulScalar(-1);
            dotprod = -dotprod;
        }

        if (dotprod > 0.9995) {
            return self_n.mulScalar(1.0 - t).add(other_n.mulScalar(t)).normalized();
        }

        var theta_0 = std.math.acos(dotprod);
        var theta = theta_0 * t;
        var sin = std.math.sin(theta);
        var sin_0 = std.math.sin(theta_0);

        var s0 = std.math.cos(theta) - (dotprod * (sin / sin_0));
        var s1 = sin / sin_0;

        return self_n.mulScalar(s0).add(other_n.mulScalar(s1));
    }

    fn square(num: f32) f32 {
        return num * num;
    }

    pub fn toMatrix(self: @This()) Mat3 {
        var x = self.data[0];
        var y = self.data[1];
        var z = self.data[2];
        var w = self.data[3];
        return Mat3{
            .data = [3][3]f32{
                [_]f32{
                    1.0 - (2.0 * (square(y) + square(z))),
                    2.0 * (x * y - z * w),
                    2.0 * (x * z + y * w),
                },
                [_]f32{
                    2.0 * (x * y + z * w),
                    1.0 - (2.0 * (square(x) + square(z))),
                    2.0 * (y * z - x * w),
                },
                [_]f32{
                    2.0 * (x * z - y * w),
                    2.0 * (y * z + x * w),
                    1.0 - (2.0 * (square(x) + square(y))),
                },
            },
        };
    }

    pub fn mulVector(self: @This(), other: Vec3) Vec3 {
        return self.toMatrix().multiplyVectorOpp(other);
    }
};

pub const Mat3 = struct {
    data: [3][3]f32,
    pub usingnamespace Matrix(3, f32, Vec3, @This());
    pub fn toMat4(self: @This()) Mat4 {
        return Mat4{
            .data = [_][4]f32{
                [_]f32{ self.data[0][0], self.data[1][0], self.data[2][0], 0.0 },
                [_]f32{ self.data[0][1], self.data[1][1], self.data[2][1], 0.0 },
                [_]f32{ self.data[0][2], self.data[1][2], self.data[2][2], 0.0 },
                [_]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        };
    }
};

pub const Mat4 = struct {
    data: [4][4]f32,
    pub usingnamespace Matrix(4, f32, Vec4, @This());

    pub fn toMat3(self: @This()) Mat3 {
        return Mat3{
            .data = [_][3]f32{
                [_]f32{ self.data[0][0], self.data[1][0], self.data[2][0] },
                [_]f32{ self.data[0][1], self.data[1][1], self.data[2][1] },
                [_]f32{ self.data[0][2], self.data[1][2], self.data[2][2] },
            },
        };
    }

    pub fn orthographic(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) @This() {
        var mat = @This().identity();
        mat.data[0][0] = 2 / (right - left);
        mat.data[1][1] = 2 / (top - bottom);
        mat.data[2][2] = -2 / (far - near);

        mat.data[3][0] = -((right + left) / (right - left));
        mat.data[3][1] = -((top + bottom) / (top - bottom));
        mat.data[3][2] = -((far + near) / (far - near));
        return mat;
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) @This() {
        var tmp = std.math.tan(fovy * 0.5);

        var mat = @This().zero();
        mat.data[0][0] = 1.0 / (aspect * tmp);
        mat.data[1][1] = 1.0 / (tmp);
        mat.data[2][2] = -(far + near) / (far - near);
        mat.data[2][3] = -1.0;
        mat.data[3][2] = -2.0 * far * near / (far - near);
        return mat;
    }

    // Stolen from ccVector.h (https://github.com/jobtalle/ccVector)
    pub fn inverse(self: @This()) @This() {
        var s = [6]f32{
            self.data[0][0] * self.data[1][1] - self.data[1][0] * self.data[0][1],
            self.data[0][0] * self.data[1][2] - self.data[1][0] * self.data[0][2],
            self.data[0][0] * self.data[1][3] - self.data[1][0] * self.data[0][3],
            self.data[0][1] * self.data[1][2] - self.data[1][1] * self.data[0][2],
            self.data[0][1] * self.data[1][3] - self.data[1][1] * self.data[0][3],
            self.data[0][2] * self.data[1][3] - self.data[1][2] * self.data[0][3],
        };
        var c = [6]f32{
            self.data[2][0] * self.data[3][1] - self.data[3][0] * self.data[2][1],
            self.data[2][0] * self.data[3][2] - self.data[3][0] * self.data[2][2],
            self.data[2][0] * self.data[3][3] - self.data[3][0] * self.data[2][3],
            self.data[2][1] * self.data[3][2] - self.data[3][1] * self.data[2][2],
            self.data[2][1] * self.data[3][3] - self.data[3][1] * self.data[2][3],
            self.data[2][2] * self.data[3][3] - self.data[3][2] * self.data[2][3],
        };
        var idet = s[0] * c[5] - s[1] * c[4] + s[2] * c[3] + s[3] * c[2] - s[4] * c[1] + s[5] * c[0];
        idet = 1.0 / idet;

        return Mat4{
            .data = [4][4]f32{
                [4]f32{
                    (self.data[1][1] * c[5] - self.data[1][2] * c[4] + self.data[1][3] * c[3]) * idet,
                    (-self.data[0][1] * c[5] + self.data[0][2] * c[4] - self.data[0][3] * c[3]) * idet,
                    (self.data[3][1] * s[5] - self.data[3][2] * s[4] + self.data[3][3] * s[3]) * idet,
                    (-self.data[2][1] * s[5] + self.data[2][2] * s[4] - self.data[2][3] * s[3]) * idet,
                },
                [4]f32{
                    (-self.data[1][0] * c[5] + self.data[1][2] * c[2] - self.data[1][3] * c[1]) * idet,
                    (self.data[0][0] * c[5] - self.data[0][2] * c[2] + self.data[0][3] * c[1]) * idet,
                    (-self.data[3][0] * s[5] + self.data[3][2] * s[2] - self.data[3][3] * s[1]) * idet,
                    (self.data[2][0] * s[5] - self.data[2][2] * s[2] + self.data[2][3] * s[1]) * idet,
                },
                [4]f32{
                    (self.data[1][0] * c[4] - self.data[1][1] * c[2] + self.data[1][3] * c[0]) * idet,
                    (-self.data[0][0] * c[4] + self.data[0][1] * c[2] - self.data[0][3] * c[0]) * idet,
                    (self.data[3][0] * s[4] - self.data[3][1] * s[2] + self.data[3][3] * s[0]) * idet,
                    (-self.data[2][0] * s[4] + self.data[2][1] * s[2] - self.data[2][3] * s[0]) * idet,
                },
                [4]f32{
                    (-self.data[1][0] * c[3] + self.data[1][1] * c[1] - self.data[1][2] * c[0]) * idet,
                    (self.data[0][0] * c[3] - self.data[0][1] * c[1] + self.data[0][2] * c[0]) * idet,
                    (-self.data[3][0] * s[3] + self.data[3][1] * s[1] - self.data[3][2] * s[0]) * idet,
                    (self.data[2][0] * s[3] - self.data[2][1] * s[1] + self.data[2][2] * s[0]) * idet,
                },
            },
        };
    }
};
