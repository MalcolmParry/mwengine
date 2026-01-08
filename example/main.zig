const std = @import("std");
const mw = @import("mwengine");
const gpu = mw.gpu;
const App = @import("App.zig");

pub fn main() !void {
    var alloc_obj = std.heap.DebugAllocator(.{}).init;
    defer _ = alloc_obj.deinit();
    const alloc = alloc_obj.allocator();

    var app: App = undefined;
    try app.init(alloc);
    defer app.deinit(alloc);
    while (try app.loop(alloc)) {}
}
