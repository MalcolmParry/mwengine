const std = @import("std");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
// xyzw
pub const Quat = Vec4;
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

pub const dir_forward: Vec3 = .{ 1, 0, 0 };
pub const dir_right: Vec3 = .{ 0, 1, 0 };
pub const dir_up: Vec3 = .{ 0, 0, 1 };

pub fn rad(degrees: anytype) @TypeOf(degrees) {
    return degrees * (pi / 180.0);
}

pub fn deg(radians: anytype) @TypeOf(radians) {
    return radians * (180.0 / pi);
}

pub fn dot(left: anytype, right: anytype) Base(@TypeOf(left)) {
    return @reduce(.Add, left * right);
}

pub fn lengthSqr(vec: anytype) Base(@TypeOf(vec)) {
    return @reduce(.Add, vec * vec);
}

pub fn length(vec: anytype) Base(@TypeOf(vec)) {
    return sqrt(lengthSqr(vec));
}

pub fn normalize(vec: anytype) @TypeOf(vec) {
    return vec / @as(@TypeOf(vec), @splat(length(vec)));
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    const ax, const ay, const az = a;
    const bx, const by, const bz = b;

    return .{
        ay * bz - az * by,
        az * bx - ax * bz,
        ax * by - ay * bx,
    };
}

pub fn changeSize(comptime len: u32, vec: anytype) @Vector(len, @typeInfo(@TypeOf(vec)).vector.child) {
    var result: @Vector(len, @typeInfo(@TypeOf(vec)).vector.child) = @splat(0);

    for (0..@typeInfo(@TypeOf(vec)).vector.len) |i| {
        if (i >= len) break;

        result[i] = vec[i];
    }

    if (len == 4)
        result[3] = 1;

    return result;
}

pub inline fn splat(T: type, len: comptime_int, x: anytype) @Vector(len, T) {
    return @splat(x);
}

pub inline fn splat2(T: type, x: anytype) @Vector(2, T) {
    return @splat(x);
}

pub inline fn splat3(T: type, x: anytype) @Vector(3, T) {
    return @splat(x);
}

pub inline fn splat4(T: type, x: anytype) @Vector(4, T) {
    return @splat(x);
}

pub inline fn i2f(T: type, x: anytype) T {
    return @floatFromInt(x);
}

pub inline fn f2i(T: type, x: anytype) T {
    return @intFromFloat(x);
}

// quaternion
pub const quat_identity: Quat = .{ 0, 0, 0, 1 };

pub fn quatFromEuler(euler: Vec3) Quat {
    const c = cos(euler / @as(Vec3, @splat(2)));
    const cr, const cp, const cy = c;
    const s = sin(euler / @as(Vec3, @splat(2)));
    const sr, const sp, const sy = s;

    return .{
        cy * cp * sr - sy * sp * cr,
        cy * sp * cr + sy * cp * sr,
        sy * cp * cr - cy * sp * sr,
        cy * cp * cr + sy * sp * sr,
    };
}

pub fn quatMul(a: Quat, b: Quat) Quat {
    const ax, const ay, const az, const aw = a;
    const bx, const by, const bz, const bw = b;

    return .{
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    };
}

pub fn quatToMatrix(quat: Quat) Mat4 {
    const n = normalize(quat);
    const x, const y, const z, const w = n;

    const xx = x * x;
    const yy = y * y;
    const zz = z * z;

    const xy = x * y;
    const xz = x * z;
    const yz = y * z;

    const wx = w * x;
    const wy = w * y;
    const wz = w * z;

    return .{
        .{ 1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0 },
        .{ 2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0 },
        .{ 2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn quatFromAxisAngle(axis: Vec3, angle: f32) Quat {
    const n = normalize(axis);
    const s = sin(angle / 2);
    const c = cos(angle / 2);

    const q: Quat = .{
        n[0] * s,
        n[1] * s,
        n[2] * s,
        c,
    };

    return normalize(q);
}

pub fn quatMulVec(q: Quat, v: Vec3) Vec3 {
    const n = normalize(q);
    const qv = changeSize(3, n);
    const t = cross(qv, v) * @as(Vec3, @splat(2));
    return v + t * @as(Vec3, @splat(n[3])) + cross(qv, t);
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
        rotateX(x),
        rotateY(y),
        rotateZ(z),
    });
}

pub fn orthographic(pos: Vec3, size: Vec3) Mat4 {
    return matMul(
        scale(.{ 2 / size[0], 2 / size[1], 1 / size[2] }),
        translate(-pos),
    );
}

pub fn perspective(aspect_ratio: f32, v_fov: f32, near: f32, far: f32) Mat4 {
    const tan_half_fov = tan(v_fov / 2);
    const a = 1 / (aspect_ratio * tan_half_fov);
    const b = 1 / tan_half_fov;
    const c = far / (near - far);
    const d = -(far * near) / (far - near);

    return matMul(
        .{
            .{ a, 0, 0, 0 },
            .{ 0, b, 0, 0 },
            .{ 0, 0, c, d },
            .{ 0, 0, -1, 0 },
        },
        to_vulkan,
    );
}

pub const to_vulkan: Mat4 = .{
    .{ 0, 1, 0, 0 },
    .{ 0, 0, -1, 0 },
    .{ -1, 0, 0, 0 },
    .{ 0, 0, 0, 1 },
};

pub const from_vulkan: Mat4 = .{
    .{ 0, 0, -1, 0 },
    .{ 1, 0, 0, 0 },
    .{ 0, -1, 0, 0 },
    .{ 0, 0, 0, 1 },
};

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

test "quaternions" {
    std.testing.refAllDecls(@This());
    const a: Quat = .{ 2, 5, 7, 3 };
    try std.testing.expect(eql(a, quatMul(a, quat_identity)));
}
