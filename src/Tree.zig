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

pub fn getPath(self: *Self, path: []const u8, buf: *std.ArrayList([]const u8)) !*Handler {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.next(); // Discard first empty
    const p = path_iter.next() orelse return error.PathNotFound;
    if (self.children.getPtr(p)) |child| {
        return child.getPath(&path_iter, buf);
    }

    if (self.children.getPtr("{}")) |child| {
        try buf.append(p);
        return child.getPath(&path_iter, buf);
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

    fn getPath(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), buf: *std.ArrayList([]const u8)) !*Handler {
        const p = path_iter.next() orelse {
            if (self.data) |handler| return handler;
            return error.PathNotFound;
        };
        if (self.children.getPtr(p)) |child| {
            return child.getPath(path_iter, buf);
        }

        if (self.children.getPtr("{}")) |child| {
            try buf.append(p);
            return child.getPath(path_iter, buf);
        }

        return error.PathNotFound;
    }
};

test "Tree" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

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

        try tree.addPath("GET/hello/world", &handler);
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        _ = try tree.getPath("GET/hello/world", &buf);
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        try testing.expect(tree.getPath("/nonexistent", &buf) == error.PathNotFound);
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

            _ = try tree.getPath("/hello/big/world", &buf);
        }

        _ = try tree.getPath("/hello/big/world", &buf);
        try testing.expect(std.mem.eql(u8, buf.items[0], "big"));
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        var handler = Handler{ .data = null, .callback = null };
        try tree.addPath("/hello/{}/world/{}", &handler);
        _ = try tree.getPath("/hello/big/world/something", &buf);
        try testing.expect(std.mem.eql(u8, buf.items[0], "big"));
        try testing.expect(std.mem.eql(u8, buf.items[1], "something"));
    }
}
