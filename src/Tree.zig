const std = @import("std");

pub const Handler = struct {
    callback: ?*anyopaque,
    data: ?*anyopaque,
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

pub fn addPath(self: *Self, path: []const u8, handler: Handler) !void {
    const alloc = self.arena.allocator();

    var path_iter = std.mem.splitScalar(u8, path, '/');
    const segment = path_iter.first();

    if (self.children.getPtr(segment)) |child| {
        return child.addPath(alloc, handler, &path_iter);
    }

    var node = Node.init(alloc);
    try node.addPath(alloc, handler, &path_iter);
    try self.children.put(try alloc.dupe(u8, segment), node);
}

pub fn getPath(self: *Self, path: []const u8) !Handler {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    const segment = path_iter.first();
    if (self.children.getPtr(segment)) |child| {
        return child.getPath(&path_iter);
    }

    return error.PathNotFound;
}

const Node = struct {
    children: std.StringHashMap(Node),
    data: ?Handler,

    fn init(alloc: std.mem.Allocator) Node {
        return .{
            .children = std.StringHashMap(Node).init(alloc),
            .data = null,
        };
    }

    fn addPath(self: *Node, alloc: std.mem.Allocator, handler: Handler, path_iter: *std.mem.SplitIterator(u8, .scalar)) !void {
        const segment = path_iter.next() orelse return;

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) {
                if (child.data != null) return error.ListenerExists;
                child.data = handler;
            }
            return child.addPath(alloc, handler, path_iter);
        }

        var node = Node.init(alloc);
        if (path_iter.peek() == null) {
            node.data = handler;
        }
        try node.addPath(alloc, handler, path_iter);
        try self.children.put(try alloc.dupe(u8, segment), node);
    }

    fn getPath(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar)) !Handler {
        const segment = path_iter.next() orelse return error.PathNotFound;

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) return child.data orelse error.PathNotFound;
            return child.getPath(path_iter);
        }

        return error.PathNotFound;
    }
};

test "Tree.addPath" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const Data = struct {
        number: u8 = 0,
    };

    const test_functions = struct {
        fn getNothing(_: ?*anyopaque) void {}
    };

    var data = Data{};

    var tree = Self.init(alloc);
    defer tree.deinit();

    try tree.addPath("GET/", .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    });
    try testing.expect(tree.children.get("GET") != null);
    try testing.expect(tree.children.get("GET").?.children.get("") != null);
    try testing.expect(tree.children.get("GET").?.children.get("").?.data != null);

    try tree.addPath("POST/hello/world", .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    });
    try testing.expect(tree.children.get("POST") != null);
    try testing.expect(tree.children.get("POST").?.children.get("hello") != null);
    try testing.expect(tree.children.get("POST").?.children.get("hello").?.children.get("world") != null);
    try testing.expect(tree.children.get("POST").?.children.get("hello").?.children.get("world").?.data != null);

    try tree.addPath("POST/bye/world", .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    });
    try testing.expect(tree.children.get("POST").?.children.get("bye") != null);
    try testing.expect(tree.children.get("POST").?.children.get("bye").?.children.get("world") != null);
    try testing.expect(tree.children.get("POST").?.children.get("bye").?.children.get("world").?.data != null);

    try testing.expect(tree.addPath("POST/bye/world", .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    }) == error.ListenerExists);

    try testing.expect(tree.addPath("GET/", .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    }) == error.ListenerExists);
}

test "Tree.getPath" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const eql = std.meta.eql;

    const Data = struct {
        number: u8 = 0,
    };

    const test_functions = struct {
        fn getNothing(_: ?*anyopaque) void {}
        fn getHello(_: ?*anyopaque) void {}
        fn getBye(_: ?*anyopaque) void {}
        fn getHelloWorld(_: ?*anyopaque) void {}
        fn getByeWolrd(_: ?*anyopaque) void {}
    };

    var data = Data{};

    var tree = Self.init(alloc);
    defer tree.deinit();

    const handler: Handler = .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    };
    try tree.addPath("GET/", handler);
    try testing.expect(eql(tree.getPath("GET/"), handler));

    const hello_world_handler: Handler = .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    };
    try tree.addPath("GET/hello/world", hello_world_handler);
    try testing.expect(tree.getPath("GET/hello") == error.PathNotFound);
    try testing.expect(eql(tree.getPath("GET/hello/world"), hello_world_handler));

    const bye_world_handler: Handler = .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    };
    try tree.addPath("GET/bye/world", bye_world_handler);
    try testing.expect(tree.getPath("GET/bye") == error.PathNotFound);
    try testing.expect(eql(tree.getPath("GET/bye/world"), bye_world_handler));

    const hello_handler: Handler = .{
        .callback = @constCast(&test_functions.getHello),
        .data = @ptrCast(&data),
    };
    try tree.addPath("GET/hello", hello_handler);
    try testing.expect(eql(tree.getPath("GET/hello"), hello_handler));

    const bye_handler: Handler = .{
        .callback = @constCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
    };
    try tree.addPath("GET/bye", bye_handler);
    try testing.expect(eql(tree.getPath("GET/bye"), bye_handler));

    const functions = struct {
        fn getIncrement(counter: *i32) void {
            counter.* += 1;
        }
        fn getDecrement(counter: *i32) void {
            counter.* -= 1;
        }
        fn getReset(counter: *i32) void {
            counter.* = 0;
        }
    };

    var counter: i32 = 0;

    {
        const increment_handler: Handler = .{
            .callback = @constCast(&functions.getIncrement),
            .data = @ptrCast(&counter),
        };
        try tree.addPath("GET/increment", increment_handler);

        const decrement_handler: Handler = .{
            .callback = @constCast(&functions.getDecrement),
            .data = @ptrCast(&counter),
        };
        try tree.addPath("GET/decrement", decrement_handler);

        const reset_handler: Handler = .{
            .callback = @constCast(&functions.getReset),
            .data = @ptrCast(&counter),
        };
        try tree.addPath("GET/reset", reset_handler);
    }

    const increment_handler = try tree.getPath("GET/increment");
    const incrementCallback: *const fn (*i32) void = @ptrCast(increment_handler.callback);

    const decrement_handler = try tree.getPath("GET/decrement");
    const decrementCallback: *const fn (*i32) void = @ptrCast(decrement_handler.callback);

    const reset_handler = try tree.getPath("GET/reset");
    const resetCallback: *const fn (*i32) void = @ptrCast(reset_handler.callback);

    try testing.expect(counter == 0);

    incrementCallback(&counter);
    try testing.expect(counter == 1);

    incrementCallback(&counter);
    try testing.expect(counter == 2);

    decrementCallback(&counter);
    try testing.expect(counter == 1);

    incrementCallback(&counter);
    try testing.expect(counter == 2);

    decrementCallback(&counter);
    try testing.expect(counter == 1);

    resetCallback(&counter);
    try testing.expect(counter == 0);
}
