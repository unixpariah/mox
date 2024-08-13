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

    try server.setListener(.GET, "/increment/{}", *i32, getIncrement, &counter);
    try server.setListener(.GET, "/decrement/{}", *i32, getDecrement, &counter);

    try server.run();
}

fn getIncrement(conn: *std.net.Server.Connection, parameters: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const number = std.fmt.parseInt(i32, parameters[0], 10) catch unreachable;
    counter.* += number;

    sendResponse(
        conn,
        200,
        std.fmt.allocPrint(
            alloc,
            "Number incremented by {} by this individual: {}, it is now {}\n",
            .{ number, conn.address, counter.* },
        ) catch unreachable,
    ) catch unreachable;
}

fn getDecrement(conn: *std.net.Server.Connection, parameters: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    std.debug.print("{any}\n", .{parameters});

    const number = std.fmt.parseInt(i32, parameters[0], 10) catch unreachable;
    counter.* -= number;

    sendResponse(
        conn,
        200,
        std.fmt.allocPrint(
            alloc,
            "Number decremented by {} by this individual: {}, it is now {}\n",
            .{ number, conn.address, counter.* },
        ) catch unreachable,
    ) catch unreachable;
}
