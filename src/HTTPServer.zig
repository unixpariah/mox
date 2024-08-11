const std = @import("std");
const Tree = @import("Tree.zig");
const Handler = @import("Tree.zig").Handler;

const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    TRACE,
    CONNECT,
    COPY,
    LINK,
    UNLINK,
};

ip: []const u8 = undefined,
port: u16 = undefined,
listener: ?std.net.Server = null,
alloc: std.mem.Allocator,
tree: Tree,

const Self = @This();

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,
        .tree = Tree.init(alloc),
    };
}

pub fn bind(self: *Self, ip: []const u8, port: u16) !void {
    const addr = try std.net.Address.resolveIp(ip, port);
    const listener = try addr.listen(.{ .reuse_address = false });

    self.listener = listener;
    self.ip = ip;
    self.port = port;
}

pub fn deinit(self: *Self) void {
    self.tree.deinit();
}

pub fn setListener(
    self: *Self,
    method: Method,
    path: []const u8,
    comptime T: type,
    listener: *const fn (connection: *std.net.Server.Connection, parameters: [][]const u8, data: T) void,
    data: T,
) !void {
    const callback: ?*anyopaque = @ptrFromInt(@intFromPtr(listener));
    var handler = Handler{ .callback = callback, .data = data };

    const buf = try self.alloc.alloc(u8, @tagName(method).len + path.len + 1);
    defer self.alloc.free(buf);
    _ = try std.fmt.bufPrint(buf, "{s}/{s}", .{ @tagName(method), path });

    try self.tree.addPath(buf, &handler);
}

pub fn run(self: *Self) !void {
    var listener = self.listener orelse return error.NotBound;
    while (listener.accept()) |*conn| {
        std.debug.print("Accepted connection from: {}\n", .{conn.address});
        var recv_buf: [4096]u8 = undefined;
        var recv_total: usize = 0;
        while (conn.stream.read(recv_buf[recv_total..])) |recv_len| {
            if (recv_len == 0) break;
            recv_total += recv_len;
            if (std.mem.containsAtLeast(u8, recv_buf[0..recv_total], 1, "\r\n\r\n")) {
                break;
            }
        } else |err| return err;

        const recv_data = recv_buf[0..recv_total];
        const header = try parseHeader(recv_data);
        const path = try parsePath(header.request_line, self.alloc);

        var buffer = std.ArrayList([]const u8).init(self.alloc);
        defer buffer.deinit();

        try self.tree.getPath(path, &buffer, @constCast(conn));
    } else |err| return err;
}

fn parseHeader(header: []const u8) !HTTPHeader {
    var http_header = HTTPHeader{
        .request_line = undefined,
        .host = undefined,
        .user_agent = undefined,
    };
    var header_iter = std.mem.tokenizeSequence(u8, header, "\r\n");
    http_header.request_line = header_iter.next() orelse return error.HeaderMalformed;
    while (header_iter.next()) |line| {
        const name = std.mem.sliceTo(line, ':');
        if (name.len == line.len) return error.HeaderMalformed;
        const header_name = std.meta.stringToEnum(HeaderNames, name) orelse continue;
        const header_val = std.mem.trimLeft(u8, line[name.len + 1 ..], " ");
        switch (header_name) {
            .Host => http_header.host = header_val,
            .@"User-Agent" => http_header.user_agent = header_val,
        }
    }

    return http_header;
}

fn parsePath(request_line: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var request_line_iter = std.mem.tokenizeScalar(u8, request_line, ' ');
    const method = request_line_iter.next().?;
    const path = request_line_iter.next().?;

    const proto = request_line_iter.next().?;
    if (!std.mem.eql(u8, proto, "HTTP/1.1")) return error.TODO;

    const buf = try alloc.alloc(u8, method.len + path.len + 1);
    _ = try std.fmt.bufPrint(buf, "{s}/{s}", .{ method, path });

    return buf;
}

const HeaderNames = enum {
    Host,
    @"User-Agent",
};

const HTTPHeader = struct {
    request_line: []const u8,
    host: []const u8,
    user_agent: []const u8,

    pub fn print(self: *HTTPHeader) void {
        std.debug.print("{s} - {s}\n", .{ self.request_line, self.host });
    }
};

test "mox" {
    const Data = struct {};

    const test_struct = struct {
        fn getHello(_: *std.net.Server.Connection, _: [][]const u8, _: *Data) void {}
    };

    const testing = std.testing;
    const alloc = testing.allocator;

    var server0 = Self.init(alloc);
    defer server0.deinit();
    try server0.bind("0.0.0.0", 8080);

    var server1 = Self.init(alloc);
    defer server1.deinit();
    try testing.expect(server1.bind("0.0.0.0", 8080) == error.AddressInUse);

    {
        var server = Self.init(alloc);
        defer server.deinit();
        try server.bind("0.0.0.0", 8081);

        var data = Data{};
        try server.setListener(
            .GET,
            "/hello",
            *Data,
            test_struct.getHello,
            &data,
        );
    }
}
