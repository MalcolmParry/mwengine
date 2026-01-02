const std = @import("std");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
// row major
pub const Mat4 = [4]Vec4;

pub const pi = std.math.pi;
pub const tau = std.math.tau;

pub const sin = std.math.sin;
pub const cos = std.math.cos;
pub const tan = std.math.tan;
pub const asin = std.math.asin;
pub const acos = std.math.acos;
pub const atan = std.math.atan;
pub const sqrt = std.math.sqrt;

pub const dir_forward: Vec3 = .{ 0, 0, -1 };
pub const dir_right: Vec3 = .{ 1, 0, 0 };
pub const dir_up: Vec3 = .{ 0, 1, 0 };
// pub const dir_forward: Vec3 = .{ 1, 0, 0 };
// pub const dir_right: Vec3 = .{ 0, 1, 0 };
// pub const dir_up: Vec3 = .{ 0, 0, 1 };

pub fn dot(left: anytype, right: anytype) Base(@TypeOf(left)) {
    return @reduce(.Add, left * right);
}

pub fn length(vec: anytype) Base(@TypeOf(vec)) {
    return sqrt(@reduce(.Add, vec * vec));
}

pub fn normalize(vec: anytype) @TypeOf(vec) {
    return vec / @as(@TypeOf(vec), @splat(length(vec)));
}

// matrix
pub const identity: Mat4 = .{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

pub fn column(mat: Mat4, index: u2) Vec4 {
    return .{
        mat[0][index],
        mat[1][index],
        mat[2][index],
        mat[3][index],
    };
}

pub fn matMul(left: Mat4, right: Mat4) Mat4 {
    var result: Mat4 = undefined;

    for (0..4) |row| {
        for (0..4) |col| {
            result[row][col] = dot(
                left[row],
                column(right, @intCast(col)),
            );
        }
    }

    return result;
}

pub fn matMulMany(operands: anytype) Mat4 {
    var result: Mat4 = identity;

    inline for (operands) |x| {
        result = matMul(result, x);
    }

    return result;
}

pub fn matMulScalar(mat: Mat4, scalar: f32) Mat4 {
    var result: Mat4 = mat;

    for (0..4) |row| {
        result[row] *= @splat(scalar);
    }

    return result;
}

pub fn matMulVec(mat: Mat4, vec: Vec4) Vec4 {
    var result: Vec4 = undefined;

    for (0..4) |row| {
        result[row] = dot(mat[row], vec);
    }

    return result;
}

pub fn translate(vec: Vec3) Mat4 {
    return .{
        .{ 1, 0, 0, vec[0] },
        .{ 0, 1, 0, vec[1] },
        .{ 0, 0, 1, vec[2] },
        .{ 0, 0, 0, 1 },
    };
}

pub fn scale(vec: Vec3) Mat4 {
    return .{
        .{ vec[0], 0, 0, 0 },
        .{ 0, vec[1], 0, 0 },
        .{ 0, 0, vec[2], 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateX(angle: f32) Mat4 {
    const c = cos(angle);
    const s = sin(angle);

    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, c, s, 0 },
        .{ 0, -s, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateY(angle: f32) Mat4 {
    const c = cos(angle);
    const s = sin(angle);

    return .{
        .{ c, 0, -s, 0 },
        .{ 0, 1, 0, 0 },
        .{ s, 0, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateZ(angle: f32) Mat4 {
    const c = cos(angle);
    const s = sin(angle);

    return .{
        .{ c, s, 0, 0 },
        .{ -s, c, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateEuler(euler_angles: Vec3) Mat4 {
    const x, const y, const z = euler_angles;

    return matMulMany(.{
        rotateZ(z),
        rotateY(y),
        rotateX(x),
    });
}

pub fn orthographic(pos: Vec3, size: Vec3) Mat4 {
    return matMul(
        scale(.{ 2 / size[0], 2 / size[1], 1 / size[2] }),
        translate(-pos),
    );
}

pub fn perspective(aspect_ratio: f32, fov: f32, near: f32, far: f32) Mat4 {
    const tan_half_fov = tan(fov / 2);
    const a = 1 / (aspect_ratio * tan_half_fov);
    const b = -1 / tan_half_fov;
    const c = far / (near - far);
    const d = -(far * near) / (far - near);

    return .{
        .{ a, 0, 0, 0 },
        .{ 0, b, 0, 0 },
        .{ 0, 0, c, d },
        .{ 0, 0, -1, 0 },
    };
}

pub fn eql(left: anytype, right: anytype) bool {
    std.debug.assert(@TypeOf(left) == @TypeOf(right));

    return switch (@typeInfo(@TypeOf(left))) {
        .vector => return @reduce(.And, left == right),
        else => @compileError("unsupported type"),
    };
}

pub fn Base(T: type) type {
    return switch (@typeInfo(T)) {
        .vector => |vec| vec.child,
        .array => |arr| Base(arr.child),
        else => @compileError("wrong type"),
    };
}

fn ToArrayReturnType(t: type) type {
    switch (@typeInfo(t)) {
        .vector => |vec| return [vec.len]vec.child,
        .array => |arr| switch (@typeInfo(arr.child)) {
            .vector => |vec| return [arr.len * vec.len]vec.child,
            else => @compileError("invalid type"),
        },
        else => @compileError("invalid type"),
    }
}

pub fn toArray(x: anytype) ToArrayReturnType(@TypeOf(x)) {
    const type_info = @typeInfo(@TypeOf(x));

    switch (type_info) {
        .vector => |vec| {
            var result: [vec.len]vec.child = undefined;

            inline for (0..vec.len) |i| {
                result[i] = x[i];
            }

            return result;
        },
        .array => |arr| switch (@typeInfo(arr.child)) {
            .vector => |vec| {
                var result: [arr.len * vec.len]vec.child = undefined;

                for (0..arr.len) |row| {
                    for (0..vec.len) |col| {
                        result[row + col * vec.len] = x[row][col];
                    }
                }

                return result;
            },
            else => @compileError("invalid type"),
        },
        else => @compileError("invalid type"),
    }
}

test "dot" {
    try std.testing.expect(dot(dir_forward, dir_right) == 0);
    try std.testing.expect(dot(dir_forward, dir_up) == 0);
    try std.testing.expect(dot(dir_forward, -dir_forward) == -1);
    try std.testing.expect(dot(dir_forward, dir_forward) == 1);
}
