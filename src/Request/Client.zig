const std = @import("std");
const Content = @import("Content.zig");

const Self = @This();

pub fn fetch(_: *const Self, method: std.http.Method, url: []const u8, body: ?Content, alloc: std.mem.Allocator) ![]const u8 {
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

    const result = try client.fetch(fetch_options);
    if (result.status != .ok) return error.Something;

    return buffer.toOwnedSlice();
}

//test "Client.fetch" {
//    const client = Self{};
//    const alloc = std.testing.allocator;
//
//    const res = try client.fetch(.GET, "http://localhost:8080/counter", null, alloc);
//    alloc.free(res);
//}
