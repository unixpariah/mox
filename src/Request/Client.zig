const std = @import("std");
const Content = @import("Content.zig");

const Self = @This();

const FetchResult = struct {
    payload: []const u8,
    status: std.http.Status,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *FetchResult) void {
        self.alloc.free(self.payload);
    }
};

pub fn fetch(_: *const Self, method: std.http.Method, url: []const u8, body: ?Content, alloc: std.mem.Allocator) !FetchResult {
    var client: std.http.Client = .{
        .allocator = alloc,
    };
    defer client.deinit();

    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();
    var fetch_options: std.http.Client.FetchOptions = .{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &buffer },
        .method = method,
    };

    if (body) |b| {
        fetch_options.payload = b.payload;
        fetch_options.headers.content_type = .{ .override = b.content_type.stringify() };
    }

    return .{
        .payload = try buffer.toOwnedSlice(),
        .status = try client.fetch(fetch_options),
        .alloc = alloc,
    };
}

//test "Client.fetch" {
//    const testing = std.testing;
//    const alloc = testing.allocator;
//    const mox = @import("mox");
//
//    // Run this in background
//    const server = mox.HTTPServer.init(alloc);
//
//    var port: u16 = 8080;
//    while (true) {
//        server.bind("127.0.0.1", port) catch {
//            port += 1;
//            continue;
//        };
//
//        break;
//    }
//
//    const fnn = struct {
//        fn thing(_: mox.Request, _: [][]const u8, _: ?*anyopaque) !void {}
//    };
//
//    _ = try server.setListener(.GET, "/api", ?*anyopaque, &fnn.thing, null);
//
//    try server.run();
//
//    const client = mox.Request.Client{};
//    const res = try client.fetch(.GET, "/api", null, alloc);
//    defer res.deinit();
//}
