const std = @import("std");
const mw = @import("mwengine");
const gpu = mw.gpu;
pub const tracy_impl = @import("tracy_impl");
pub const tracy = @import("tracy");
const App = @import("App.zig");

pub fn main() !void {
    var tracy_allocator: tracy.Allocator = .{ .parent = std.heap.smp_allocator };
    const alloc = tracy_allocator.allocator();

    var app: App = undefined;
    try app.init(alloc);
    defer app.deinit(alloc);
    while (try app.loop(alloc)) {}
}
