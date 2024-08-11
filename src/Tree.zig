const std = @import("std");

pub const Handler = struct {
    data: ?*anyopaque,
    callback: ?*anyopaque,
};

arena: std.heap.ArenaAllocator,
children: std.StringHashMap(Node),

const Self = @This();

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .children = std.StringHashMap(Node).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
    self.children.deinit();
}

pub fn addPath(self: *Self, path: []const u8, handler: *Handler) !void {
    const alloc = self.arena.allocator();

    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.next(); // Discard first empty

    const p = path_iter.next() orelse return;

    if (self.children.getPtr(p)) |child| {
        return child.addPath(alloc, handler, &path_iter);
    }

    var node = Node.new(alloc);
    try node.addPath(alloc, handler, &path_iter);
    try self.children.put(p, node);
}

pub fn getPath(self: *Self, path: []const u8, buf: *std.ArrayList([]const u8), conn: *std.net.Server.Connection) !void {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.next(); // Discard first empty
    const p = path_iter.next() orelse return;
    if (self.children.getPtr(p)) |child| {
        return child.getPath(&path_iter, buf, conn);
    }

    if (self.children.getPtr("{}")) |child| {
        try buf.append(p);
        return child.getPath(&path_iter, buf, conn);
    }

    return error.PathNotFound;
}

const Node = struct {
    children: std.StringHashMap(Node),
    data: ?*Handler,

    fn new(alloc: std.mem.Allocator) Node {
        return .{ .children = std.StringHashMap(Node).init(alloc), .data = null };
    }

    fn addPath(self: *Node, alloc: std.mem.Allocator, handler: *Handler, path_iter: *std.mem.SplitIterator(u8, .scalar)) !void {
        const p = path_iter.next() orelse {
            if (self.data != null) return error.ListenerExists;
            self.data = handler;
            return;
        };

        if (self.children.getPtr(p)) |child| {
            return child.addPath(alloc, handler, path_iter);
        }

        var node = Node.new(alloc);
        try node.addPath(alloc, handler, path_iter);
        try self.children.put(p, node);
    }

    fn getPath(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), buf: *std.ArrayList([]const u8), conn: *std.net.Server.Connection) !void {
        const p = path_iter.next() orelse return error.PathNotFound;
        if (self.children.getPtr(p)) |child| {
            return child.getPath(path_iter, buf, conn);
        }

        if (self.children.getPtr("{}")) |child| {
            try buf.append(p);
            return child.getPath(path_iter, buf, conn);
        }

        if (self.data) |handler| {
            const callback: *const fn (*std.net.Server.Connection, [][]const u8, data: ?*anyopaque) void = @ptrCast(handler.callback);
            callback(conn, buf.items, handler.data);
            return;
        }

        return error.PathNotFound;
    }
};

test "Tree" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const addr = try std.net.Address.resolveIp("0.0.0.0", 8083);
    var listener = try addr.listen(.{ .reuse_address = true });
    var conn = try listener.accept();

    const Data = struct {};

    const test_struct = struct {
        fn getHello(_: *std.net.Server.Connection, _: [][]const u8, _: *Data) void {}
    };

    var data = Data{};

    var tree = Self.init(alloc);
    defer tree.deinit();
    {
        const callback: ?*anyopaque = @ptrFromInt(@intFromPtr(&test_struct.getHello));
        var handler = Handler{ .data = &data, .callback = callback };

        try tree.addPath("/hello/world", &handler);
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        try tree.getPath("/hello/world", &buf, &conn);
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        try testing.expect(tree.getPath("/nonexistent", &buf, &conn) == error.PathNotFound);
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();

        {
            var handler = Handler{ .data = null, .callback = null };
            try tree.addPath("/hello/{}/world", &handler);
        }

        {
            var handler = Handler{ .data = null, .callback = null };
            try testing.expect(tree.addPath("/hello/{}/world", &handler) == error.ListenerExists);

            try tree.getPath("/hello/big/world", &buf, &conn);
        }

        try tree.getPath("/hello/big/world", &buf, &conn);
        try testing.expect(std.mem.eql(u8, buf.items[0], "big"));
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        var handler = Handler{ .data = null, .callback = null };
        try tree.addPath("/hello/{}/world/{}", &handler);
        try tree.getPath("/hello/big/world/something", &buf, &conn);
        try testing.expect(std.mem.eql(u8, buf.items[0], "big"));
        try testing.expect(std.mem.eql(u8, buf.items[1], "something"));
    }
}
