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
    var counter: i32 = 0;

    try server.setListener(.GET, "/increment", *i32, getIncrement, &counter);
    try server.setListener(.GET, "/decrement", *i32, getDecrement, &counter);

    try server.run();
}

fn getIncrement(conn: *std.net.Server.Connection, counter: *i32) void {
    counter.* += 1;
    std.debug.print(
        "This nice individual incremented number by 1: {}\nThe number is now {}\n",
        .{ conn.address, counter.* },
    );
}

fn getDecrement(conn: *std.net.Server.Connection, counter: *i32) void {
    counter.* -= 1;
    std.debug.print(
        "This not very nice individual decremented number by 1: {}\nThe number is now {}\n",
        .{ conn.address, counter.* },
    );
}
