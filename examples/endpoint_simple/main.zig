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
    try server.setListener(.GET, "/exit", *mox, getExit, &server);

    try server.run();
}

fn getExit(_: mox.Request, _: [][]const u8, server: *mox) !void {
    server.stop();
}

fn postCounterIncrement(request: mox.Request, parameters: [][]const u8, counter: *i32) anyerror!void {
    const number = try std.fmt.parseInt(i32, parameters[0], 10);
    counter.* += number;

    try request.respond(.{ .Text = try std.fmt.allocPrint(
        request.arena.child_allocator,
        "Number incremented by {} by this individual: {}\n",
        .{ number, request.conn.address },
    ) }, 200);
}

fn postCounterDecrement(request: mox.Request, parameters: [][]const u8, counter: *i32) anyerror!void {
    const number = std.fmt.parseInt(i32, parameters[0], 10) catch unreachable;
    counter.* -= number;

    try request.respond(
        .{ .Text = try std.fmt.allocPrint(
            request.arena.child_allocator,
            "Number decremented by {} by this individual: {}\n",
            .{ number, request.conn.address },
        ) },
        200,
    );
}

fn postCounterReset(request: mox.Request, _: [][]const u8, counter: *i32) anyerror!void {
    counter.* = 0;

    try request.respond(
        .{ .Text = try std.fmt.allocPrint(
            request.arena.child_allocator,
            "Number reseted by this individual: {}\n",
            .{request.conn.address},
        ) },
        200,
    );
}

fn getCounter(request: mox.Request, _: [][]const u8, counter: *i32) anyerror!void {
    try request.respond(
        .{ .Text = try std.fmt.allocPrint(
            request.arena.child_allocator,
            "Number is: {}\n",
            .{counter.*},
        ) },
        200,
    );
}
