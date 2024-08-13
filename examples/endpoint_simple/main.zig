const std = @import("std");
const mox = @import("mox");

pub fn main() !void {
    var server = mox.init(std.heap.page_allocator);
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
    try server.setListener(.POST, "/counter/increment/{}", *i32, postCounterIncrement, &counter);
    try server.setListener(.POST, "/counter/decrement/{}", *i32, postCounterDecrement, &counter);
    try server.setListener(.POST, "/counter/reset", *i32, postCounterReset, &counter);
    try server.setListener(.GET, "/counter", *i32, getCounter, &counter);

    try server.run();
}

fn postCounterIncrement(request: mox.Request, parameters: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const number = std.fmt.parseInt(i32, parameters[0], 10) catch unreachable;
    counter.* += number;

    request.respond(.{ .Text = std.fmt.allocPrint(
        alloc,
        "Number incremented by {} by this individual: {}\n",
        .{ number, request.conn.address },
    ) catch unreachable }, 200) catch unreachable;
}

fn postCounterDecrement(request: mox.Request, parameters: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const number = std.fmt.parseInt(i32, parameters[0], 10) catch unreachable;
    counter.* -= number;

    request.respond(
        .{ .Text = std.fmt.allocPrint(
            alloc,
            "Number decremented by {} by this individual: {}\n",
            .{ number, request.conn.address },
        ) catch unreachable },
        200,
    ) catch unreachable;
}

fn postCounterReset(request: mox.Request, _: [][]const u8, counter: *i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    counter.* = 0;

    request.respond(
        .{ .Text = std.fmt.allocPrint(
            alloc,
            "Number reseted by this individual: {}\n",
            .{request.conn.address},
        ) catch unreachable },
        200,
    ) catch unreachable;
}

fn getCounter(request: mox.Request, _: [][]const u8, counter: *i32) void {
    std.debug.print("{s}\n", .{request.header.body.?});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    request.respond(
        .{ .Text = std.fmt.allocPrint(
            alloc,
            "Number is: {}\n",
            .{counter.*},
        ) catch unreachable },
        200,
    ) catch unreachable;
}
