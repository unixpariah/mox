const std = @import("std");

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
}

pub fn addPath(self: *Self, path: []const u8) !void {
    const alloc = self.arena.allocator();

    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.next(); // Discard first empty

    const p = path_iter.next() orelse return;

    if (self.children.getPtr(p)) |child| {
        return child.addPath(alloc, &path_iter);
    }

    var node = Node.new(alloc);
    try node.addPath(alloc, &path_iter);
    try self.children.put(p, node);
}

pub fn getPath(self: *Self, path: []const u8, buf: *std.ArrayList([]const u8)) !void {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.next(); // Discard first empty
    const p = path_iter.next() orelse return;
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

    fn new(alloc: std.mem.Allocator) Node {
        return .{ .children = std.StringHashMap(Node).init(alloc) };
    }

    fn addPath(self: *Node, alloc: std.mem.Allocator, path_iter: *std.mem.SplitIterator(u8, .scalar)) !void {
        const p = path_iter.next() orelse return;
        if (self.children.getPtr(p)) |child| {
            return child.addPath(alloc, path_iter);
        }

        var node = Node.new(alloc);
        try node.addPath(alloc, path_iter);
        try self.children.put(p, node);
    }

    fn getPath(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), buf: *std.ArrayList([]const u8)) !void {
        const p = path_iter.next() orelse return;
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
    const alloc = std.heap.page_allocator;
    const assert = std.debug.assert;

    var tree = Self.init(alloc);
    {
        try tree.addPath("/hello/world");
        var buf = std.ArrayList([]const u8).init(alloc);
        defer buf.deinit();
        try tree.getPath("/hello/world", &buf);
    }

    {
        var buf = std.ArrayList([]const u8).init(alloc);
        defer buf.deinit();
        assert(tree.getPath("/nonexistent", &buf) == error.PathNotFound);
    }

    {
        var buf = std.ArrayList([]const u8).init(alloc);
        defer buf.deinit();
        try tree.addPath("/hello/{}/world");
        try tree.getPath("/hello/big/world", &buf);
        assert(std.mem.eql(u8, buf.items[0], "big"));
    }

    {
        var buf = std.ArrayList([]const u8).init(alloc);
        defer buf.deinit();
        try tree.addPath("/hello/{}/world/{}");
        try tree.getPath("/hello/big/world/something", &buf);
        assert(std.mem.eql(u8, buf.items[0], "big"));
        assert(std.mem.eql(u8, buf.items[1], "something"));
    }
}
