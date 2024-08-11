const std = @import("std");
const Tree = @import("Tree.zig");

const Handler = struct {
    data: ?*anyopaque,
    callback: ?*anyopaque,
};

const MethodPath = union(enum) {
    GET: []const u8,
    DELETE: []const u8,
    POST: []const u8,
};

ip: []const u8 = undefined,
port: u16 = undefined,
listener: std.net.Server = undefined,
sources: std.StringHashMap(Handler),
alloc: std.mem.Allocator,

const Self = @This();

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,
        .sources = std.StringHashMap(Handler).init(alloc),
    };
}

pub fn bind(self: *Self, ip: []const u8, port: u16) !void {
    const addr = try std.net.Address.resolveIp(ip, port);
    self.listener = try addr.listen(.{ .reuse_address = false });

    self.ip = ip;
    self.port = port;
}

pub fn setListener(
    self: *Self,
    method: MethodPath,
    comptime T: type,
    listener: *const fn (connection: *std.net.Server.Connection, parameters: [][]const u8, data: T) void,
    data: T,
) !void {
    const callback: ?*anyopaque = @ptrFromInt(@intFromPtr(listener));

    const tag_name = @tagName(method);
    const value = switch (method) {
        .GET => |val| val,
        .POST => |val| val,
        .DELETE => |val| val,
    };

    const buf = try self.alloc.alloc(u8, tag_name.len + value.len + 1);
    _ = try std.fmt.bufPrint(buf, "{s} {s}", .{ tag_name, value });

    try self.sources.put(buf, .{ .data = data, .callback = callback });
}

pub fn run(self: *Self) !void {
    while (self.listener.accept()) |*conn| {
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
        const path = try parsePath(header.request_line);

        if (self.sources.get(path)) |source| {
            const callback: *const fn (*std.net.Server.Connection, [][]const u8, data: ?*anyopaque) void = @ptrCast(source.callback);
            callback(@constCast(conn), &[_][]const u8{}, source.data);
        }
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

fn parsePath(request_line: []const u8) ![]const u8 {
    var request_line_iter = std.mem.tokenizeScalar(u8, request_line, ' ');
    const method = request_line_iter.next().?;

    const path = request_line_iter.next().?;

    const proto = request_line_iter.next().?;
    if (!std.mem.eql(u8, proto, "HTTP/1.1")) return error.TODO;

    const buf = try std.heap.page_allocator.alloc(u8, method.len + path.len + 1);
    _ = try std.fmt.bufPrint(buf, "{s} {s}", .{ method, path });

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
