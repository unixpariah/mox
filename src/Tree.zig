const std = @import("std");
const Request = @import("Request.zig");

const method_map = std.StaticStringMap(u4).initComptime(.{
    .{ "GET", 0 },
    .{ "PUT", 1 },
    .{ "HEAD", 2 },
    .{ "POST", 3 },
    .{ "TRACE", 4 },
    .{ "PATCH", 5 },
    .{ "DELETE", 6 },
    .{ "CONNECT", 7 },
    .{ "OPTIONS", 8 },
});

pub const Handler = struct {
    callback: *const fn (request: Request, parameters: [][]const u8, counter: *i32) anyerror!void,
    error_handler: ?*const fn (Request, anyerror) void,
    data: ?*anyopaque,
};

arena: std.heap.ArenaAllocator,
children: [9]Node,

const Self = @This();

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .children = .{
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
            Node.init(alloc),
        },
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
    for (&self.children) |*child| {
        child.children.deinit();
    }
}

pub fn addPath(self: *Self, method: std.http.Method, path: []const u8, handler: Handler) !void {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.first();
    const index: usize = @intCast(method_map.get(@tagName(method)) orelse @panic("Unsupported method"));
    try self.children[index].addPath(self.arena.allocator(), handler, &path_iter);
}

pub fn getPath(self: *Self, method: std.http.Method, path: []const u8, buffer: *std.ArrayList([]const u8)) !*Handler {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.first();
    const index: usize = @intCast(method_map.get(@tagName(method)) orelse @panic("Unsupported method"));
    return self.children[index].getPath(&path_iter, buffer);
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

    fn getPath(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), buffer: *std.ArrayList([]const u8)) !*Handler {
        const segment = path_iter.next() orelse return error.PathNotFound;

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) return if (child.data) |*data| data else error.PathNotFound;
            return child.getPath(path_iter, buffer);
        }

        if (self.children.getPtr("{}")) |child| {
            try buffer.append(segment);
            if (path_iter.peek() == null) return if (child.data) |*data| data else error.PathNotFound;
            return child.getPath(path_iter, buffer);
        }

        return error.PathNotFound;
    }

    fn addErrorHandler(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), error_handler: *?anyopaque) !void {
        const segment = path_iter.next() orelse return error.PathNotFound;

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) {
                if (child.data == null) return error.PathNotFound;
                child.data.?.error_handler = error_handler;
            }
            return child.addErrorHandler(&path_iter, error_handler);
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
        fn getNothing(_: Request, _: [][]const u8, _: ?*anyopaque) !void {}
    };

    var data = Data{};

    var tree = Self.init(alloc);
    defer tree.deinit();

    try tree.addPath(.GET, "/", .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    });

    try testing.expect(tree.children[0].children.get("") != null);
    try testing.expect(tree.children[0].children.get("").?.data != null);

    try tree.addPath(.POST, "/hello/world", .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    });
    try testing.expect(tree.children[3].children.get("hello") != null);
    try testing.expect(tree.children[3].children.get("hello").?.children.get("world") != null);
    try testing.expect(tree.children[3].children.get("hello").?.children.get("world").?.data != null);

    try tree.addPath(.POST, "/bye/world", .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    });
    try testing.expect(tree.children[3].children.get("bye").?.children.get("world") != null);
    try testing.expect(tree.children[3].children.get("bye").?.children.get("world").?.data != null);

    try testing.expect(tree.addPath(.POST, "/bye/world", .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    }) == error.ListenerExists);

    try testing.expect(tree.addPath(.GET, "/", .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    }) == error.ListenerExists);

    try tree.addPath(.GET, "/{}", .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    });
    try testing.expect(tree.children[0].children.get("{}") != null);
    try testing.expect(tree.children[0].children.get("{}").?.data != null);
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
    var void_buffer = std.ArrayList([]const u8).init(alloc);
    defer void_buffer.deinit();

    var tree = Self.init(alloc);
    defer tree.deinit();

    const handler: Handler = .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    };
    try tree.addPath(.GET, "/", handler);
    try testing.expect(eql((try tree.getPath(.GET, "/", &void_buffer)).*, handler));

    const hello_world_handler: Handler = .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    };
    try tree.addPath(.GET, "/hello/world", hello_world_handler);
    try testing.expect(tree.getPath(.GET, "/hello", &void_buffer) == error.PathNotFound);
    try testing.expect(eql((try tree.getPath(.GET, "/hello/world", &void_buffer)).*, hello_world_handler));

    const bye_world_handler: Handler = .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    };
    try tree.addPath(.GET, "/bye/world", bye_world_handler);
    try testing.expect(tree.getPath(.GET, "/bye", &void_buffer) == error.PathNotFound);
    try testing.expect(eql((try tree.getPath(.GET, "/bye/world", &void_buffer)).*, bye_world_handler));

    const hello_handler: Handler = .{
        .callback = @ptrCast(&test_functions.getHello),
        .data = @ptrCast(&data),
        .error_handler = null,
    };
    try tree.addPath(.GET, "/hello", hello_handler);
    try testing.expect(eql((try tree.getPath(.GET, "/hello", &void_buffer)).*, hello_handler));

    const bye_handler: Handler = .{
        .callback = @ptrCast(&test_functions.getNothing),
        .data = @ptrCast(&data),
        .error_handler = null,
    };
    try tree.addPath(.GET, "/bye", bye_handler);
    try testing.expect(eql((try tree.getPath(.GET, "/bye", &void_buffer)).*, bye_handler));

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
            .callback = @ptrCast(&functions.getIncrement),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        try tree.addPath(.GET, "/increment", increment_handler);

        const decrement_handler: Handler = .{
            .callback = @ptrCast(&functions.getDecrement),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        try tree.addPath(.GET, "/decrement", decrement_handler);

        const reset_handler: Handler = .{
            .callback = @ptrCast(&functions.getReset),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        try tree.addPath(.GET, "/reset", reset_handler);
    }

    {
        const increment_handler = try tree.getPath(.GET, "/increment", &void_buffer);
        const incrementCallback: *const fn (*i32) void = @ptrCast(increment_handler.callback);

        const decrement_handler = try tree.getPath(.GET, "/decrement", &void_buffer);
        const decrementCallback: *const fn (*i32) void = @ptrCast(decrement_handler.callback);

        const reset_handler = try tree.getPath(.GET, "/reset", &void_buffer);
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

    const functions2 = struct {
        fn getIncrement(buffer: [][]const u8, inner_counter: *i32) void {
            const num = std.fmt.parseInt(i32, buffer[0], 10) catch unreachable;
            inner_counter.* += num;
        }
        fn getDecrement(buffer: [][]const u8, inner_counter: *i32) void {
            const num = std.fmt.parseInt(i32, buffer[0], 10) catch unreachable;
            inner_counter.* -= num;
        }
        fn getDecrementBy5(inner_counter: *i32) void {
            inner_counter.* -= 5;
        }
    };

    {
        const increment_handler: Handler = .{
            .callback = @ptrCast(&functions2.getIncrement),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        try tree.addPath(.GET, "/increment/{}", increment_handler);

        const decrement_handler: Handler = .{
            .callback = @ptrCast(&functions2.getDecrement),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        try tree.addPath(.GET, "/decrement/{}", decrement_handler);

        const decrement_by_5_handler: Handler = .{
            .callback = @ptrCast(&functions2.getDecrementBy5),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        try tree.addPath(.GET, "/decrement/by_five", decrement_by_5_handler);
    }

    {
        var increment_buffer = std.ArrayList([]const u8).init(alloc);
        defer increment_buffer.deinit();
        const increment_handler = try tree.getPath(.GET, "/increment/10", &increment_buffer);
        const incrementCallback: *const fn ([][]const u8, *i32) void = @ptrCast(increment_handler.callback);
        try testing.expect(increment_buffer.items.len == 1);
        try testing.expect(std.mem.eql(u8, increment_buffer.items[0], "10"));

        var decrement_buffer = std.ArrayList([]const u8).init(alloc);
        defer decrement_buffer.deinit();
        const decrement_handler = try tree.getPath(.GET, "/decrement/10", &decrement_buffer);
        const decrementCallback: *const fn ([][]const u8, *i32) void = @ptrCast(decrement_handler.callback);
        try testing.expect(decrement_buffer.items.len == 1);
        try testing.expect(std.mem.eql(u8, decrement_buffer.items[0], "10"));

        const decrement_by_5_handler = try tree.getPath(.GET, "/decrement/by_five", &void_buffer);
        const decrementBy5Callback: *const fn (*i32) void = @ptrCast(decrement_by_5_handler.callback);

        const reset_handler = try tree.getPath(.GET, "/reset", &void_buffer);
        const resetCallback: *const fn (*i32) void = @ptrCast(reset_handler.callback);

        try testing.expect(counter == 0);

        incrementCallback(increment_buffer.items, &counter);
        try testing.expect(counter == 10);

        incrementCallback(increment_buffer.items, &counter);
        try testing.expect(counter == 20);

        decrementCallback(decrement_buffer.items, &counter);
        try testing.expect(counter == 10);

        incrementCallback(increment_buffer.items, &counter);
        try testing.expect(counter == 20);

        decrementCallback(decrement_buffer.items, &counter);
        try testing.expect(counter == 10);

        decrementBy5Callback(&counter);
        try testing.expect(counter == 5);

        resetCallback(&counter);
        try testing.expect(counter == 0);
    }
}
