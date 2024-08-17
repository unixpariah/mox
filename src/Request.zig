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

// TODO
pub fn reply(self: *const Self, content: Content, response_code: u10) !void {
    switch (content.content_type) {
        .TEXT => return self.respondBody(content.payload, response_code),
        .JSON => return self.respondJson(content.payload, response_code),
        .HTML => {},
    }
}

fn respondJson(self: *const Self, json: []const u8, response_code: u10) !void {
    const response = "HTTP/1.1 {} {s} \r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: application/json; charset=utf8\r\n" ++
        "Content-Length: {}\r\n" ++
        "\r\n";

    const status_description: std.http.Status = @enumFromInt(response_code);
    _ = try self.conn.stream.writer().print(response, .{ response_code, @tagName(status_description), json.len });
    _ = try self.conn.stream.writer().write(json);
}

fn respondBody(self: *const Self, body: []const u8, response_code: u10) !void {
    const response = "HTTP/1.1 {} {s} \r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: text/html; charset=utf8\r\n" ++
        "Content-Length: {}\r\n" ++
        "\r\n";

    const status_description: std.http.Status = @enumFromInt(response_code);
    _ = try self.conn.stream.writer().print(response, .{ response_code, @tagName(status_description), body.len });
    _ = try self.conn.stream.writer().write(body);
}
