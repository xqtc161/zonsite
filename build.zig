const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addAnonymousImport("site.zon", .{
        .root_source_file = b.path("site.zon"),
    });

    const gen = b.addExecutable(.{
        .name = "zonsite",
        .root_module = root_module,
    });

    const run = b.addRunArtifact(gen);
    const html = run.captureStdOut(.{ .basename = "index.html" });

    const install_html = b.addInstallFile(html, "index.html");
    const install_css = b.addInstallFile(b.path("src/style.css"), "style.css");
    const install_favicon = b.addInstallDirectory(.{
        .source_dir = b.path("favicon"),
        .install_dir = .prefix,
        .install_subdir = "",
    });

    b.getInstallStep().dependOn(&install_html.step);
    b.getInstallStep().dependOn(&install_css.step);
    b.getInstallStep().dependOn(&install_favicon.step);
}
