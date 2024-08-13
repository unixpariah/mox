const std = @import("std");

const Self = @This();

/// Send request, caller is responsible for freeing response buffer
pub fn send(_: *const Self, method: std.http.Method, url: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var client: std.http.Client = .{
        .allocator = alloc,
    };
    defer client.deinit();

    var buffer = std.ArrayList(u8).init(alloc);
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &buffer },
        .method = method,
    });

    if (result.status != .ok) return error.HttpFailed;

    return buffer.toOwnedSlice();
}
