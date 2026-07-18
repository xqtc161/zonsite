const std = @import("std");
const Writer = std.Io.Writer;
const mem = std.mem;

const source: [:0]const u8 = @embedFile("site.zon");

pub fn main(init: std.process.Init) !void {
    var buf: [64 * 1024]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &buf);
    const w = &fw.interface;
    try render(w, source);
    try w.flush();
}

fn render(w: *Writer, src: [:0]const u8) !void {
    try w.writeAll(html_head);

    var tok = std.zig.Tokenizer.init(src);
    var index: usize = 0;

    while (true) {
        const t = tok.next();
        try writeEscaped(w, src[index..t.loc.start]);
        if (t.tag == .eof) break;

        const text = src[t.loc.start..t.loc.end];
        const class = classOf(t.tag);

        if (t.tag == .string_literal) {
            try writeString(w, text, class);
        } else {
            try w.print("<span class=\"{s}\">", .{class});
            try writeEscaped(w, text);
            try w.writeAll("</span>");
        }

        index = t.loc.end;
    }

    try w.writeAll(html_tail);
}

fn classOf(tag: std.zig.Token.Tag) []const u8 {
    return switch (tag) {
        .string_literal, .multiline_string_literal_line => "tok-string",
        .number_literal => "tok-number",
        .identifier => "tok-ident",
        .doc_comment, .container_doc_comment => "tok-comment",
        else => "tok-punct",
    };
}

//
// strings + heuristic linkification
//

const LinkKind = enum { none, url, email };

fn linkKind(s: []const u8) LinkKind {
    if (mem.startsWith(u8, s, "https://") or mem.startsWith(u8, s, "http://")) return .url;

    // ths is a bit ugly but should do for now
    // checks if there is an '@' somewhere with a '.' after it and no spaces
    if (mem.indexOfScalar(u8, s, '@')) |at| {
        if (at > 0 and mem.indexOfScalarPos(u8, s, at, '.') != null and mem.indexOfScalar(u8, s, ' ') == null) return .email;
    }
    return .none;
}

fn writeString(w: *Writer, text: []const u8, class: []const u8) !void {
    try w.print("<span class=\"{s}\">", .{class});

    linkified: {
        if (text.len < 2 or text[0] != '"') break :linkified;
        const inner = text[1 .. text.len - 1]; //strip quotes
        const kind = linkKind(inner);
        if (kind == .none) break :linkified;

        try w.writeByte('"');
        try w.writeAll("<a href=\"");
        if (kind == .email) try w.writeAll("mailto:");
        try writeAttr(w, inner);
        try w.writeAll("\">");
        try writeEscaped(w, inner);
        try w.writeAll("</a>\"</span>");
        return;
    }
    try writeEscaped(w, text);
    try w.writeAll("</span>");
}

//
// escaping
//

fn writeEscaped(w: *Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '&' => try w.writeAll("&amp;"),
        else => try w.writeByte(c),
    };
}

fn writeAttr(w: *Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '"' => try w.writeAll("&quot;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        else => try w.writeByte(c),
    };
}

const html_head =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\<meta charset="utf-8">
    \\<meta name="viewport" content="width-device-width, initial-scale=1">
    \\<title>tila.cat</title>
    \\<link rel="stylesheet" href="style.css">
    \\<link rel="icon" type="image/png" href="/favicon-96x96.png" sizes="96x96" />
    \\<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    \\<link rel="shortcut icon" href="/favicon.ico" />
    \\<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
    \\<meta name="apple-mobile-web-app-title" content="tila.cat" />
    \\</head>
    \\<body>
    \\<pre><code>
;

const html_tail =
    \\</code></pre>
    \\</body>
    \\</html>
    \\
;
