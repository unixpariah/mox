const std = @import("std");
const mox = @import("mox");

pub fn main() !void {
    var server = mox.HTTPServer.init(std.heap.page_allocator);
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
    _ = try server.setListener(.POST, "/counter/modify/{}", *i32, postCounterModify, &counter);
    _ = try server.setListener(.POST, "/counter/reset", *i32, postCounterReset, &counter);
    _ = try server.setListener(.GET, "/counter", *i32, getCounter, &counter);
    _ = try server.setListener(.GET, "/exit", *mox.HTTPServer, getExit, &server);

    try server.run();
}

fn getExit(_: mox.Request, _: [][]const u8, server: *mox.HTTPServer) !void {
    server.stop();
}

fn postCounterModify(request: mox.Request, parameters: [][]const u8, counter: *i32) anyerror!void {
    const number = try std.fmt.parseInt(i32, parameters[0], 10);
    counter.* += number;

    try request.reply(.{ .content_type = .TEXT, .payload = try std.fmt.allocPrint(
        request.alloc,
        "Number incremented by {} by this individual: {}\n",
        .{ number, request.conn.address },
    ) }, 200);

    if (counter.* > 10) return error.Over10;
}

fn postCounterReset(request: mox.Request, _: [][]const u8, counter: *i32) anyerror!void {
    counter.* = 0;

    try request.reply(
        .{ .content_type = .TEXT, .payload = try std.fmt.allocPrint(
            request.alloc,
            "Number reseted by this individual: {}\n",
            .{request.conn.address},
        ) },
        200,
    );
}

fn getCounter(request: mox.Request, _: [][]const u8, counter: *i32) anyerror!void {
    try request.reply(
        .{ .content_type = .TEXT, .payload = try std.fmt.allocPrint(
            request.alloc,
            "Number is: {}\n",
            .{counter.*},
        ) },
        200,
    );
}
