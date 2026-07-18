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

    // pre-scan for foldable blocks; scanFolds does all the brace matching so
    // the loop below just consults it by offset
    var fold_buf: [64]Fold = undefined;
    const folds = fold_buf[0..scanFolds(src, &fold_buf)];

    var tok = std.zig.Tokenizer.init(src);
    var index: usize = 0; // end of what we've written, to recover skipped gaps
    var fold_id: usize = 0; // unique id to pair each checkbox with its label

    while (true) {
        const t = tok.next();
        // dump the whitespace/comments before this token as-is
        try writeEscaped(w, src[index..t.loc.start]);
        index = t.loc.end;
        if (t.tag == .eof) break;

        const text = src[t.loc.start..t.loc.end];
        switch (t.tag) {
            // fold open
            // wraps block in a checkbox toggle (see openFold)
            .l_brace => if (foldOpen(folds, t.loc.start)) |n| {
                try openFold(w, fold_id, n, text);
                fold_id += 1;
            } else try writeToken(w, text, t.tag),
            // fold close
            // shut the wrapper before the brace so the } stays visible
            .r_brace => {
                if (foldClose(folds, t.loc.start)) try w.writeAll("</span></span>");
                try writeToken(w, text, t.tag);
            },
            else => try writeToken(w, text, t.tag),
        }
    }

    try w.writeAll(html_tail);
}

// foldable block byte offsets of its braces and how many source lines it spans
const Fold = struct {
    open: usize,
    close: usize,
    lines: usize,
};

fn foldOpen(folds: []const Fold, off: usize) ?usize {
    for (folds) |f| if (f.open == off) return f.lines;
    return null;
}

fn foldClose(folds: []const Fold, off: usize) bool {
    for (folds) |f| if (f.close == off) return true;
    return false;
}

// a hidden checkbox toggles the body, the brace is its label, the line count is
// the collapsed hint. inline spans so it goes inside the <pre> (unlike <details>)
fn openFold(w: *Writer, id: usize, lines: usize, brace: []const u8) !void {
    try w.print("<span class=\"fold-block\"><input type=\"checkbox\" class=\"fold-toggle\" id=\"fold{d}\" checked><label class=\"fold-brace\" for=\"fold{d}\">", .{ id, id });
    try writeToken(w, brace, .l_brace);
    try w.print("</label><span class=\"fold-hint\"> {d} lines </span><span class=\"fold-body\">", .{lines});
}

// find every brace marked with a //fold comment; record its span and line count
fn scanFolds(src: [:0]const u8, out: []Fold) usize {
    var tok = std.zig.Tokenizer.init(src);
    var opens: [64]usize = undefined; // open-brace offset per depth
    var flags: [64]bool = undefined; // brace marked to fold?
    var depth: usize = 0;
    var n: usize = 0;

    var cur = tok.next();
    while (cur.tag != .eof) {
        const next = tok.next();
        switch (cur.tag) {
            .l_brace => {
                if (depth < opens.len) {
                    opens[depth] = cur.loc.start;
                    // a //fold marker in the gap right after the brace
                    flags[depth] = hasFoldMarker(src[cur.loc.end..next.loc.start]);
                }
                depth += 1;
            },
            .r_brace => {
                if (depth > 0) depth -= 1;
                if (depth < opens.len and flags[depth] and n < out.len) {
                    out[n] = .{
                        .open = opens[depth],
                        .close = cur.loc.start,
                        .lines = mem.count(u8, src[opens[depth]..cur.loc.end], "\n"),
                    };
                    n += 1;
                }
            },
            else => {},
        }
        cur = next;
    }
    return n;
}

// a //fold (or "// fold") line comment in the gap after a brace marks that
// block as foldable
fn hasFoldMarker(gap: []const u8) bool {
    return mem.indexOf(u8, gap, "//fold") != null or
        mem.indexOf(u8, gap, "// fold") != null;
}

fn writeToken(w: *Writer, text: []const u8, tag: std.zig.Token.Tag) !void {
    const class = classOf(tag);

    // determine if string literal is a link or not
    if (tag == .string_literal) return writeString(w, text, class);

    try w.print("<span class=\"{s}\">", .{class});
    try writeEscaped(w, text);
    try w.writeAll("</span>");
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

    // if string literal is a url or email wrap the contents in an <a> tag
    // to make it clickable or otherwise break and render as plain text
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
        '\'' => try w.writeAll("&#39;"),
        else => try w.writeByte(c),
    };
}

fn writeAttr(w: *Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '"' => try w.writeAll("&quot;"),
        '\'' => try w.writeAll("&#39;"),
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
