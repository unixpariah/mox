const std = @import("std");

const HeaderNames = enum {
    Host,
    @"User-Agent",
};

request_line: []const u8,
host: []const u8,
user_agent: []const u8,
body: ?[]const u8,

const Self = @This();

pub fn parse(header: []const u8) !Self {
    var http_header = Self{
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

    const header_end = std.mem.indexOf(u8, header, "\r\n\r\n") orelse return error.HeaderMalformed;
    http_header.body = header[header_end + 4 ..];

    return http_header;
}
