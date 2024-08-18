const std = @import("std");
pub const Client = @import("Request/Client.zig");
pub const Header = @import("Request/HTTPHeader.zig");
const Content = @import("Request/Content.zig");

conn: *const std.net.Server.Connection,
arena_alloc: std.mem.Allocator,
alloc: std.mem.Allocator,
client: Client,
header: Header,

const Self = @This();

pub fn init(conn: *const std.net.Server.Connection, header: Header, arena: *std.heap.ArenaAllocator) Self {
    return .{
        .conn = conn,
        .arena_alloc = arena.allocator(),
        .alloc = arena.child_allocator,
        .client = Client{},
        .header = header,
    };
}

pub fn reply(self: *const Self, content: Content, response_code: u10) !void {
    const response = "HTTP/1.1 {} {s} \r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: {s}; charset=utf8\r\n" ++
        "Content-Length: {}\r\n" ++
        "\r\n";

    const status_description: std.http.Status = @enumFromInt(response_code);
    _ = try self.conn.stream.writer().print(response, .{
        response_code,
        @tagName(status_description),
        content.content_type.stringify(),
        content.payload.len,
    });

    _ = try self.conn.stream.writer().write(content.payload);
}
