const std = @import("std");
const mox = @import("mox");
const sendResponse = @import("mox").sendResponse;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var server = mox.init(alloc);
    var port: u16 = 8080;
    while (true) {
        server.bind("127.0.0.1", port) catch {
            port += 1;
            continue;
        };

        break;
    }

    std.debug.print("Listening on: {s}:{}", .{ server.ip, server.port });

    var counter: i32 = 0;

    try server.setListener(.GET, "/increment", *i32, getIncrement, &counter);
    try server.setListener(.GET, "/decrement/thing/{}", *i32, getDecrement, &counter);

    try server.run();
}

fn getIncrement(conn: *std.net.Server.Connection, _: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    counter.* += 1;
    sendResponse(
        conn,
        200,
        std.fmt.allocPrint(
            alloc,
            "Number incremented by 1 by this individual: {}, it is now {}\n",
            .{ conn.address, counter.* },
        ) catch unreachable,
    ) catch unreachable;
}

fn getDecrement(conn: *std.net.Server.Connection, _: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    counter.* -= 1;
    sendResponse(
        conn,
        200,
        std.fmt.allocPrint(
            alloc,
            "Number decremented by 1 by this individual: {}, it is now {}\n",
            .{ conn.address, counter.* },
        ) catch unreachable,
    ) catch unreachable;
}
