const std = @import("std");

const ContentType = enum {
    TEXT,
    JSON,
    HTML,

    pub fn stringify(self: *const ContentType) []const u8 {
        const content_map = std.StaticStringMap([]const u8).initComptime(.{
            .{ "TEXT", "text/plain" },
            .{ "JSON", "application/json" },
            .{ "HTML", "text/html" },
        });

        return content_map.get(@tagName(self.*)).?;
    }
};

content_type: ContentType,
payload: []const u8,
