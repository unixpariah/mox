const std = @import("std");
pub const Client = @import("Request/Client.zig");
pub const Header = @import("Request/HTTPHeader.zig");

conn: *const std.net.Server.Connection,
arena: std.heap.ArenaAllocator,
alloc: std.mem.Allocator,
client: Client,
header: Header,

const Self = @This();

pub fn init(conn: *const std.net.Server.Connection, header: Header, alloc: std.mem.Allocator) Self {
    var arena = std.heap.ArenaAllocator.init(alloc);

    return .{
        .conn = conn,
        .arena = arena,
        .alloc = arena.allocator(),
        .client = Client{},
        .header = header,
    };
}

pub fn deinit(self: *const Self) void {
    self.arena.deinit();
}

pub fn respond(self: *const Self, content: Content, response_code: u10) !void {
    switch (content) {
        .Text => |text| return self.respondBody(text, response_code),
        .Json => |json| return self.respondJson(json, response_code),
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

const Content = union(enum) {
    Text: []const u8,
    Json: []const u8,
};
