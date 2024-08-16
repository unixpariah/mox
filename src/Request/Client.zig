const std = @import("std");

const Self = @This();

const Content = union(enum) {
    TEXT: []const u8,
    JSON: []const u8,
    HTML: []const u8,

    fn getContent(self: *const Content) []const u8 {
        return switch (self.*) {
            .TEXT => |data| data,
            .JSON => |data| data,
            .HTML => |data| data,
        };
    }

    fn getContentType(self: *const Content) []const u8 {
        return switch (self.*) {
            .TEXT => "text/plain",
            .JSON => "application/json",
            .HTML => "text/html",
        };
    }
};

pub fn fetch(_: *const Self, method: std.http.Method, url: []const u8, body: ?Content, alloc: std.mem.Allocator) ![]const u8 {
    var client: std.http.Client = .{
        .allocator = alloc,
    };
    defer client.deinit();

    var buffer = std.ArrayList(u8).init(alloc);
    var fetch_options: std.http.Client.FetchOptions = .{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &buffer },
        .method = method,
    };

    if (body) |b| {
        fetch_options.payload = b.getContent();
        fetch_options.headers.content_type = .{ .override = b.getContentType() };
    }

    const result = try client.fetch(fetch_options);
    if (result.status != .ok) return error.Something;

    return buffer.toOwnedSlice();
}

//test "Client.fetch" {
//    const client = Self{};
//    const alloc = std.testing.allocator;
//
//    const res = try client.fetch(.GET, "http://localhost:8081/exit", null, alloc);
//    alloc.free(res);
//}
