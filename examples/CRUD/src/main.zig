const std = @import("std");
const mox = @import("mox");

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
    std.debug.print("Listening on {s}:{}\n", .{ server.ip, server.port });

    try server.setListener(.GET, "/hello", ?*anyopaque, getHello, null);
    try server.setListener(.GET, "/hello/world", ?*anyopaque, getHelloWorld, null);

    try server.run();
}

fn getHello(conn: *std.net.Server.Connection, _: ?*anyopaque) void {
    std.debug.print("Received connection from: {}\n", .{conn.address});
}

fn getHelloWorld(conn: *std.net.Server.Connection, _: ?*anyopaque) void {
    std.debug.print("Received connection from this nice idividual: {}\n", .{conn.address});
}
