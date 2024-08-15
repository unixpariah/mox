const std = @import("std");
const Tree = @import("Tree.zig");
const Request = @import("Request.zig");
const UUID = @import("UUID.zig");

ip: []const u8 = undefined,
port: u16 = undefined,
listener: ?std.net.Server = null,
alloc: std.mem.Allocator,
tree: Tree,
error_handler: struct { function: *const fn (Request, anyerror, ?*anyopaque) void, data: ?*anyopaque },
exit: bool = false,

fn errorHandler(_: Request, _: anyerror, _: ?*anyopaque) void {
    unreachable;
}

const Self = @This();

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,
        .tree = Tree.init(alloc),
        .error_handler = .{
            .function = @ptrCast(&errorHandler),
            .data = null,
        },
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
    method: std.http.Method,
    path: []const u8,
    comptime T: type,
    listener: *const fn (request: Request, parameters: [][]const u8, data: T) anyerror!void,
    data: T,
) !void {
    const buffer = try std.fmt.allocPrint(
        self.alloc,
        "{s}{s}",
        .{ @tagName(method), path },
    );
    defer self.alloc.free(buffer);

    try self.tree.addPath(buffer, .{ .callback = @ptrCast(listener), .data = @ptrCast(data), .error_handler = null });
}

pub fn addErrorHandler(
    self: *Self,
    comptime T: type,
    error_handler: *const fn (request: Request, err: anyerror, data: T) void,
    data: T,
) void {
    self.error_handler = .{
        .data = @ptrCast(data),
        .function = error_handler,
    };
}

pub fn run(self: *Self) !void {
    var listener = self.listener orelse return error.NotBound;
    while (listener.accept()) |*conn| {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();

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
        const header = try Request.Header.parse(recv_data);
        const path = try parsePath(header.request_line, arena.allocator());

        const request = Request.init(conn, header, &arena);

        var buffer = std.ArrayList([]const u8).init(arena.allocator());
        defer buffer.deinit();

        //                                Remove trailing uninitialized memory
        const handler = self.tree.getPath(path[0 .. path.len - 1], &buffer) catch |err| switch (err) {
            error.PathNotFound => {
                try request.respond(.{ .Text = "NOT FOUND" }, 404);
                continue;
            },
            else => return err,
        };

        const callback: *const fn (Request, [][]const u8, ?*anyopaque) anyerror!void = @ptrCast(handler.callback);
        callback(request, buffer.items, handler.data) catch |err| {
            if (handler.error_handler != null) {
                const error_handler: *const fn (err: anyerror) void = @ptrCast(handler.error_handler);
                error_handler(err);
                continue;
            }

            const error_handler: *const fn (Request, anyerror, ?*anyopaque) void = @ptrCast(self.error_handler.function);
            error_handler(request, err, self.error_handler.data);
        };

        if (self.exit) break;
    } else |err| return err;
}

pub fn stop(self: *Self) void {
    self.exit = true;
}

fn parseHeader(header: []const u8) !HTTPHeader {
    var http_header = HTTPHeader{
        .request_line = undefined,
        .host = undefined,
        .user_agent = undefined,
        .body = null,
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
    if (!std.mem.eql(u8, proto, "HTTP/1.1")) return error.ProtoNotSupported;

    const buf = try alloc.alloc(u8, method.len + path.len + 1);
    _ = try std.fmt.bufPrint(buf, "{s}{s}", .{ method, path });

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
    body: ?[]const u8,
};

test "mox.setListener" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var mox = Self.init(alloc);
    defer mox.deinit();

    const test_struct = struct {
        fn getHello(_: Request, _: [][]const u8, _: ?*i32) anyerror!void {}
    };

    try mox.setListener(.GET, "/hello", ?*i32, test_struct.getHello, null);
    var void_buffer = std.ArrayList([]const u8).init(alloc);
    defer void_buffer.deinit();
    _ = try mox.tree.getPath("GET/hello", &void_buffer);

    try testing.expect(mox.setListener(
        .GET,
        "/hello",
        ?*i32,
        test_struct.getHello,
        null,
    ) == error.ListenerExists);
    try mox.setListener(.POST, "/hello", ?*i32, test_struct.getHello, null);
    _ = try mox.tree.getPath("POST/hello", &void_buffer);
    try mox.setListener(.GET, "/hello/{}", ?*i32, test_struct.getHello, null);
    try mox.setListener(.GET, "/hello/someone", ?*i32, test_struct.getHello, null);

    var buffer = std.ArrayList([]const u8).init(alloc);
    defer buffer.deinit();
    _ = try mox.tree.getPath("GET/hello/world", &buffer);
    try testing.expect(std.mem.eql(u8, buffer.items[0], "world"));
    buffer.clearAndFree();

    _ = try mox.tree.getPath("GET/hello/someone", &buffer);
    try testing.expect(buffer.items.len == 0);
}

test "mox.bind" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var server0 = Self.init(alloc);
    defer server0.deinit();

    var port: u16 = 8080;
    while (true) {
        server0.bind("127.0.0.1", port) catch {
            port += 1;
            continue;
        };

        break;
    }

    var server1 = Self.init(alloc);
    defer server1.deinit();
    try testing.expect(server1.bind("127.0.0.1", port) == error.AddressInUse);

    var server2 = Self.init(alloc);
    defer server2.deinit();
    try server2.bind("127.0.0.1", port + 1);
}

test "mox.run" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const Data = struct {};

    const test_struct = struct {
        fn getHello(_: Request, _: [][]const u8, _: *Data) anyerror!void {}
    };

    var server = Self.init(alloc);
    defer server.deinit();

    try testing.expect(server.run() == error.NotBound);

    var port: u16 = 8080;
    while (true) {
        server.bind("127.0.0.1", port) catch {
            port += 1;
            continue;
        };

        break;
    }

    var data = Data{};
    try server.setListener(
        .GET,
        "/hello",
        *Data,
        test_struct.getHello,
        &data,
    );

    // TODO: Make it run in background
    // try server.run();
}

test "mox.addErrorHandler" {
    const testing = std.testing;

    const err = struct {
        fn error_handler(_: Request, _: anyerror, _: ?*anyopaque) void {}
    };

    var mox = Self.init(testing.allocator);
    mox.addErrorHandler(?*anyopaque, err.error_handler, null);

    try testing.expectEqual(err.error_handler, mox.error_handler.function);
}
