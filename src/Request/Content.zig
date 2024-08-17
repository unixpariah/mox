const ContentType = enum {
    TEXT,
    JSON,
    HTML,

    pub fn stringify(self: *const ContentType) []const u8 {
        return switch (self.*) {
            .TEXT => "text/plain",
            .JSON => "application/json",
            .HTML => "text/html",
        };
    }
};

content_type: ContentType,
payload: []const u8,
