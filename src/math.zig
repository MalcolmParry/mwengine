const std = @import("std");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
// column major
pub const Mat4 = [4]Vec4;

pub const pi = std.math.pi;
pub const tau = std.math.tau;

pub const sin = std.math.sin;
pub const cos = std.math.cos;
pub const tan = std.math.tan;
pub const asin = std.math.asin;
pub const acos = std.math.acos;
pub const atan = std.math.atan;

pub const dir_forward: Vec4 = .{ 1, 0, 0, 0 };
pub const dir_right: Vec4 = .{ 0, 1, 0, 0 };
pub const dir_up: Vec4 = .{ 0, 0, 1, 0 };

pub fn dot(left: anytype, right: anytype) @typeInfo(@TypeOf(left)).vector.child {
    return @reduce(.Add, left * right);
}

// matrix
pub const identity: Mat4 = .{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

pub fn matMul(left: Mat4, right: Mat4) Mat4 {
    var result: Mat4 = undefined;

    for (0..4) |row| {
        for (0..4) |col| {
            result[col][row] = dot(right[col], Vec4{
                left[0][row],
                left[1][row],
                left[2][row],
                left[3][row],
            });
        }
    }

    return result;
}

pub fn matMulScalar(mat: Mat4, scalar: f32) Mat4 {
    var result: Mat4 = undefined;

    for (0..4) |row| {
        for (0..4) |col| {
            result[col][row] = mat[col][row] * scalar;
        }
    }

    return result;
}

// pub fn matMulVec(mat: Mat4, vec: Vec4) Vec4 {
//     var result: Vec4 = undefined;
//
//     for (0..4) |row| {
//         result[row] = dot(mat[row], vec);
//     }
//
//     return result;
// }

pub fn translate(vec: Vec3) Mat4 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ vec[0], vec[1], vec[2], 1 },
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
        .{ 0, c, -s, 0 },
        .{ 0, s, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateY(angle: f32) Mat4 {
    const c = cos(angle);
    const s = sin(angle);

    return .{
        .{ c, 0, s, 0 },
        .{ 0, 1, 0, 0 },
        .{ -s, 0, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateZ(angle: f32) Mat4 {
    const c = cos(angle);
    const s = sin(angle);

    return .{
        .{ c, -s, 0, 0 },
        .{ s, c, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateEuler(euler_angles: Vec3) Mat4 {
    const x, const y, const z = euler_angles;

    const zy = matMul(rotateZ(z), rotateY(y));
    return matMul(zy, rotateX(x));
}

pub fn orthographic(pos: Vec3, size: Vec3) Mat4 {
    return matMul(
        scale(.{ 2 / size[0], 2 / size[1], 1 / size[2] }),
        translate(-pos),
    );
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

                for (0..arr.len) |i| {
                    for (0..vec.len) |ii| {
                        result[ii + i * vec.len] = x[i][ii];
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
