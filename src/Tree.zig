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
    const segment = path_iter.next() orelse return error.PathNotFound;

    if (self.children.getPtr(segment)) |child| {
        return child.addPath(alloc, handler, &path_iter);
    }

    var node = Node.new(alloc);
    try node.addPath(alloc, handler, &path_iter);
    const segment_alloc = try alloc.alloc(u8, segment.len);
    @memcpy(segment_alloc, segment);
    try self.children.put(segment_alloc, node);
}

pub fn getPath(self: *Self, path: []const u8, buf: *std.ArrayList([]const u8)) !*Handler {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    const segment = path_iter.next() orelse return error.PathNotFound;
    if (self.children.getPtr(segment)) |child| {
        return child.getPath(&path_iter, buf);
    }

    if (self.children.getPtr("{}")) |child| {
        try buf.append(segment);
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
        fn getHello(_: [][]const u8, _: *Data) void {
            std.debug.print("Hello world\n", .{});
        }
    };

    var data = Data{};

    var tree = Self.init(alloc);
    defer tree.deinit();
    {
        const callback: ?*anyopaque = @ptrFromInt(@intFromPtr(&test_struct.getHello));
        var handler = Handler{ .data = &data, .callback = callback };

        try tree.addPath("GET/hello/world", &handler);
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        const stored_handler = try tree.getPath("GET/hello/world", &buf);
        try testing.expect(handler.data == stored_handler.data);
        try testing.expect(handler.callback == stored_handler.callback);

        const callback_fn: *const fn ([][]const u8, ?*anyopaque) void = @ptrCast(stored_handler.callback);
        callback_fn(&[_][]const u8{}, null);
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        try testing.expect(tree.getPath("GET/nonexistent", &buf) == error.PathNotFound);
    }

    {
        var handler = Handler{ .data = null, .callback = @ptrFromInt(@intFromPtr(&test_struct.getHello)) };
        try tree.addPath("GET/hello/{}/world", &handler);
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        const stored_handler = try tree.getPath("GET/hello/whatever/world", &buf);

        try testing.expect(handler.data == stored_handler.data);
        try testing.expect(handler.callback == stored_handler.callback);

        const callback_fn: *const fn ([][]const u8, ?*anyopaque) void = @ptrCast(stored_handler.callback);
        callback_fn(&[_][]const u8{}, null);
    }

    {
        var handler = Handler{ .data = null, .callback = null };
        try testing.expect(tree.addPath("GET/hello/{}/world", &handler) == error.ListenerExists);

        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        const stored_handler = try tree.getPath("GET/hello/big/world", &buf);

        const callback_fn: *const fn ([][]const u8, ?*anyopaque) void = @ptrCast(stored_handler.callback);
        callback_fn(&[_][]const u8{}, null);
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        const stored_handler = try tree.getPath("GET/hello/big/world", &buf);
        try testing.expect(std.mem.eql(u8, buf.items[0], "big"));

        const callback_fn: *const fn ([][]const u8, ?*anyopaque) void = @ptrCast(stored_handler.callback);
        callback_fn(&[_][]const u8{}, null);
    }

    {
        var buf = std.ArrayList([]const u8).init(arena.allocator());
        defer buf.deinit();
        var handler = Handler{ .data = null, .callback = null };
        try tree.addPath("GET/hello/{}/world/{}", &handler);
        _ = try tree.getPath("GET/hello/big/world/something", &buf);

        try testing.expect(std.mem.eql(u8, buf.items[0], "big"));
        try testing.expect(std.mem.eql(u8, buf.items[1], "something"));
    }
}
