const std = @import("std");

pub const Error = error{InvalidUUID};

bytes: [16]u8,

const Self = @This();

pub fn init() Self {
    var uuid = Self{ .bytes = undefined };

    std.crypto.random.bytes(&uuid.bytes);
    uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40;
    uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80;
    return uuid;
}

pub fn toString(self: Self, slice: []u8) void {
    var string: [36]u8 = formatUuid(self);
    std.mem.copyForwards(u8, slice, &string);
}

fn formatUuid(self: Self) [36]u8 {
    var buf: [36]u8 = undefined;
    buf[8] = '-';
    buf[13] = '-';
    buf[18] = '-';
    buf[23] = '-';
    inline for (encoded_pos, 0..) |i, j| {
        buf[i + 0] = hex[self.bytes[j] >> 4];
        buf[i + 1] = hex[self.bytes[j] & 0x0f];
    }
    return buf;
}

const encoded_pos = [16]u8{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };

const hex = "0123456789abcdef";

const hex_to_nibble = [256]u8{
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};

pub fn format(
    self: Self,
    comptime layout: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    if (layout.len != 0 and layout[0] != 's')
        @compileError("Unsupported format specifier for UUID type: '" ++ layout ++ "'.");

    const buf = formatUuid(self);
    try std.fmt.format(writer, "{s}", .{buf});
}

pub fn parse(buf: []const u8) Error!Self {
    var uuid = Self{ .bytes = undefined };

    if (buf.len != 36 or buf[8] != '-' or buf[13] != '-' or buf[18] != '-' or buf[23] != '-')
        return Error.InvalidUUID;

    inline for (encoded_pos, 0..) |i, j| {
        const hi = hex_to_nibble[buf[i + 0]];
        const lo = hex_to_nibble[buf[i + 1]];
        if (hi == 0xff or lo == 0xff) {
            return Error.InvalidUUID;
        }
        uuid.bytes[j] = hi << 4 | lo;
    }

    return uuid;
}

pub const zero: Self = .{ .bytes = .{0} ** 16 };

pub fn newV4() Self {
    return Self.init();
}

test "UUID.parse" {
    const testing = std.testing;

    const uuids = [_][]const u8{
        "d0cd8041-0504-40cb-ac8e-d05960d205ec",
        "3df6f0e4-f9b1-4e34-ad70-33206069b995",
        "f982cf56-c4ab-4229-b23c-d17377d000be",
        "6b9f53be-cf46-40e8-8627-6b60dc33def8",
        "c282ec76-ac18-4d4a-8a29-3b94f5c74813",
        "00000000-0000-0000-0000-000000000000",
    };

    for (uuids) |uuid| {
        try testing.expectFmt(uuid, "{}", .{try Self.parse(uuid)});
    }

    const wrong_uuids = [_][]const u8{
        "3df6f0e4-f9b1-4e34-ad70-33206069b99",
        "3df6f0e4-f9b1-4e34-ad70-33206069b9912",
        "3df6f0e4-f9b1-4e34-ad70_33206069b9912",
        "zdf6f0e4-f9b1-4e34-ad70-33206069b995",
    };

    for (wrong_uuids) |uuid| {
        try testing.expectError(Error.InvalidUUID, Self.parse(uuid));
    }
}

test "check toString works" {
    const testing = std.testing;

    const uuid1 = Self.init();

    var string1: [36]u8 = undefined;
    var string2: [36]u8 = undefined;

    uuid1.toString(&string1);
    uuid1.toString(&string2);

    try testing.expectEqual(string1, string2);
}
