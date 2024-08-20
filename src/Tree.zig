const std = @import("std");
const Request = @import("Request.zig");

const ErrorHandler = struct {
    error_handler: *const fn (Request, anyerror, ?*anyopaque) anyerror!void,
    data: ?*anyopaque,
    nested_error_handler: ?*ErrorHandler = null,

    pub fn addErrorHandler(self: *Handler, comptime T: type, listener: *const fn (Request, anyerror, T) anyerror!void, data: T) *ErrorHandler {
        self.error_handler = .{
            .error_handler = @ptrCast(listener),
            .data = data,
        };

        return &self.error_handler.?;
    }
};

pub const Handler = struct {
    callback: *const fn (Request, [][]const u8, ?*anyopaque) anyerror!void,
    data: ?*anyopaque,
    error_handler: ?ErrorHandler = null,

    pub fn addErrorHandler(self: *Handler, comptime T: type, listener: *const fn (Request, anyerror, T) anyerror!void, data: T) *ErrorHandler {
        self.error_handler = .{
            .error_handler = @ptrCast(listener),
            .data = data,
        };

        return &self.error_handler.?;
    }
};

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

pub fn addPath(self: *Self, method: std.http.Method, path: []const u8, handler: Handler) !*Handler {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.first();
    const index: usize = @intCast(method_map.get(@tagName(method)) orelse return error.Unsupported);
    return self.children[index].addPath(self.arena.allocator(), handler, &path_iter);
}

pub fn getPath(self: *Self, method: std.http.Method, path: []const u8, buffer: *std.ArrayListUnmanaged([]const u8)) ?*Handler {
    var path_iter = std.mem.splitScalar(u8, path, '/');
    _ = path_iter.first();
    const index: usize = @intCast(method_map.get(@tagName(method)).?);
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

    fn addPath(self: *Node, alloc: std.mem.Allocator, handler: Handler, path_iter: *std.mem.SplitIterator(u8, .scalar)) !*Handler {
        const segment = path_iter.next().?;

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) {
                if (child.data != null) return error.ListenerExists;
                child.data = handler;
                return &child.data.?;
            }
            return child.addPath(alloc, handler, path_iter);
        }

        const node = Node.init(alloc);
        try self.children.put(try alloc.dupe(u8, segment), node);
        var child = self.children.getPtr(segment).?;
        if (path_iter.peek() == null) {
            child.data = handler;
            return &child.data.?;
        }
        return child.addPath(alloc, handler, path_iter);
    }

    fn getPath(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), buffer: *std.ArrayListUnmanaged([]const u8)) ?*Handler {
        const segment = path_iter.next().?; // Will return before it ever goes null so safe to unwrap

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) return if (child.data) |*data| data else null;
            return child.getPath(path_iter, buffer);
        }

        if (self.children.getPtr("{}")) |child| {
            buffer.appendAssumeCapacity(segment);
            if (path_iter.peek() == null) return if (child.data) |*data| data else null;
            return child.getPath(path_iter, buffer);
        }

        return null;
    }

    fn addErrorHandler(self: *Node, path_iter: *std.mem.SplitIterator(u8, .scalar), error_handler: *?anyopaque) !void {
        const segment = path_iter.next().?; // Will return before it ever goes null so safe to unwrap

        if (self.children.getPtr(segment)) |child| {
            if (path_iter.peek() == null) {
                if (child.data == null) return null;
                child.data.?.error_handler = error_handler;
            }
            return child.addErrorHandler(&path_iter, error_handler);
        }

        return null;
    }
};

test "Tree.addPath" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var tree = Self.init(alloc);
    defer tree.deinit();

    const handler = Handler{
        .callback = undefined,
        .data = null,
        .error_handler = null,
    };

    _ = try tree.addPath(.GET, "/", handler);
    _ = try tree.addPath(.POST, "/hello/world", handler);
    _ = try tree.addPath(.GET, "/hello/world", handler);
    _ = try tree.addPath(.GET, "/{}", handler);

    try testing.expectEqual(tree.addPath(.GET, "/", handler), error.ListenerExists);
    try testing.expectEqual(tree.addPath(.GET, "/{}", handler), error.ListenerExists);

    try testing.expect(tree.children[0].children.get("") != null);
    try testing.expect(tree.children[0].children.get("").?.data != null);

    try testing.expect(tree.children[3].children.get("hello") != null);
    try testing.expect(tree.children[3].children.get("hello").?.children.get("world") != null);
    try testing.expect(tree.children[3].children.get("hello").?.children.get("world").?.data != null);

    try testing.expect(tree.children[0].children.get("hello").?.children.get("world") != null);
    try testing.expect(tree.children[0].children.get("hello").?.children.get("world").?.data != null);

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

    var tree = Self.init(alloc);
    defer tree.deinit();

    const handlers: [3]Handler = .{
        .{
            .callback = @ptrCast(&test_functions.getNothing),
            .data = @ptrCast(&data),
            .error_handler = null,
        },
        .{
            .callback = @ptrCast(&test_functions.getHello),
            .data = @ptrCast(&data),
            .error_handler = null,
        },
        .{
            .callback = @ptrCast(&test_functions.getNothing),
            .data = @ptrCast(&data),
            .error_handler = null,
        },
    };

    _ = try tree.addPath(.GET, "/", handlers[0]);
    _ = try tree.addPath(.GET, "/hello/world", handlers[0]);
    _ = try tree.addPath(.GET, "/bye/world", handlers[0]);

    try testing.expect(eql((tree.getPath(.GET, "/", undefined)).?.*, handlers[0]));

    try testing.expectEqual(tree.getPath(.GET, "/hello", undefined), null);
    try testing.expectEqual(tree.getPath(.GET, "/hello/world", undefined).?.*, handlers[0]);

    try testing.expectEqual(tree.getPath(.GET, "/bye", undefined), null);
    try testing.expectEqual(tree.getPath(.GET, "/bye/world", undefined).?.*, handlers[0]);

    _ = try tree.addPath(.GET, "/hello", handlers[1]);
    try testing.expectEqual(tree.getPath(.GET, "/hello", undefined).?.*, handlers[1]);

    _ = try tree.addPath(.GET, "/bye", handlers[2]);
    try testing.expectEqual(tree.getPath(.GET, "/bye", undefined).?.*, handlers[2]);

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

    _ = try tree.addPath(.GET, "/increment", .{
        .callback = @ptrCast(&functions.getIncrement),
        .data = @ptrCast(&counter),
        .error_handler = null,
    });

    _ = try tree.addPath(.GET, "/decrement", .{
        .callback = @ptrCast(&functions.getDecrement),
        .data = @ptrCast(&counter),
        .error_handler = null,
    });

    _ = try tree.addPath(.GET, "/reset", .{
        .callback = @ptrCast(&functions.getReset),
        .data = @ptrCast(&counter),
        .error_handler = null,
    });

    {
        const increment_handler = tree.getPath(.GET, "/increment", undefined).?;
        const incrementCallback: *const fn (*i32) void = @ptrCast(increment_handler.callback);

        const decrement_handler = tree.getPath(.GET, "/decrement", undefined).?;
        const decrementCallback: *const fn (*i32) void = @ptrCast(decrement_handler.callback);

        const reset_handler = tree.getPath(.GET, "/reset", undefined).?;
        const resetCallback: *const fn (*i32) void = @ptrCast(reset_handler.callback);

        try testing.expectEqual(counter, 0);

        incrementCallback(&counter);
        try testing.expectEqual(counter, 1);

        incrementCallback(&counter);
        try testing.expectEqual(counter, 2);

        decrementCallback(&counter);
        try testing.expectEqual(counter, 1);

        incrementCallback(&counter);
        try testing.expectEqual(counter, 2);

        decrementCallback(&counter);
        try testing.expectEqual(counter, 1);

        resetCallback(&counter);
        try testing.expectEqual(counter, 0);
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
        _ = try tree.addPath(.GET, "/increment/{}", increment_handler);

        const decrement_handler: Handler = .{
            .callback = @ptrCast(&functions2.getDecrement),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        _ = try tree.addPath(.GET, "/decrement/{}", decrement_handler);

        const decrement_by_5_handler: Handler = .{
            .callback = @ptrCast(&functions2.getDecrementBy5),
            .data = @ptrCast(&counter),
            .error_handler = null,
        };
        _ = try tree.addPath(.GET, "/decrement/by_five", decrement_by_5_handler);
    }

    {
        var increment_buffer = std.ArrayListUnmanaged([]const u8).initBuffer(try alloc.alloc([]const u8, 1));
        defer increment_buffer.deinit(alloc);
        const increment_handler = tree.getPath(.GET, "/increment/10", &increment_buffer).?;
        const incrementCallback: *const fn ([][]const u8, *i32) void = @ptrCast(increment_handler.callback);
        try testing.expect(increment_buffer.items.len == 1);
        try testing.expect(std.mem.eql(u8, increment_buffer.items[0], "10"));

        var decrement_buffer = std.ArrayListUnmanaged([]const u8).initBuffer(try alloc.alloc([]const u8, 1));
        defer decrement_buffer.deinit(alloc);
        const decrement_handler = tree.getPath(.GET, "/decrement/10", &decrement_buffer).?;
        const decrementCallback: *const fn ([][]const u8, *i32) void = @ptrCast(decrement_handler.callback);
        try testing.expect(decrement_buffer.items.len == 1);
        try testing.expect(std.mem.eql(u8, decrement_buffer.items[0], "10"));

        const decrement_by_5_handler = tree.getPath(.GET, "/decrement/by_five", undefined).?;
        const decrementBy5Callback: *const fn (*i32) void = @ptrCast(decrement_by_5_handler.callback);

        const reset_handler = tree.getPath(.GET, "/reset", undefined).?;
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

test "Handler.addErrorHandler" {
    const testing = std.testing;

    const test_struct = struct {
        fn function(_: Request, _: [][]const u8, _: ?*anyopaque) !void {}
        fn functionErr(_: Request, _: anyerror, _: ?*anyopaque) !void {}
    };

    var handler = Handler{
        .data = null,
        .error_handler = null,
        .callback = &test_struct.function,
    };

    const err_handler = handler.addErrorHandler(?*anyopaque, &test_struct.functionErr, null);

    try testing.expectEqual(err_handler.error_handler, test_struct.functionErr);
    try testing.expect(handler.error_handler != null);
}
