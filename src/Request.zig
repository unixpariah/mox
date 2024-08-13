const std = @import("std");
const Client = @import("Client.zig");

conn: *const std.net.Server.Connection,
alloc: std.mem.Allocator,
client: Client,

const Self = @This();

pub fn respond(self: *const Self, content: Content, response_code: u10) !void {
    switch (content) {
        .Text => |text| return self.respondBody(text, response_code),
    }
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
};
