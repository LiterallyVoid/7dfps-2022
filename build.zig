const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("7dfps-2022", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addIncludePath("deps/glad/include/");
    exe.addCSourceFile("deps/glad/src/gl.c", &.{});

    exe.addIncludePath("deps/stb/");
    exe.addCSourceFile("deps/stb/stb.c", &.{});

    exe.addIncludePath("deps/libogg-1.3.5/include/");
    exe.addCSourceFiles(
        &.{
            "deps/libogg-1.3.5/src/bitwise.c",
            "deps/libogg-1.3.5/src/framing.c",
        },
        &.{},
    );

    exe.addIncludePath("deps/libvorbis-1.3.7/include/");
    exe.addIncludePath("deps/libvorbis-1.3.7/lib/");
    exe.addCSourceFiles(
        &.{
            "deps/libvorbis-1.3.7/lib/mdct.c",
            "deps/libvorbis-1.3.7/lib/smallft.c",
            "deps/libvorbis-1.3.7/lib/block.c",
            "deps/libvorbis-1.3.7/lib/envelope.c",
            "deps/libvorbis-1.3.7/lib/window.c",
            "deps/libvorbis-1.3.7/lib/lsp.c",
            "deps/libvorbis-1.3.7/lib/lpc.c",
            "deps/libvorbis-1.3.7/lib/analysis.c",
            "deps/libvorbis-1.3.7/lib/synthesis.c",
            "deps/libvorbis-1.3.7/lib/psy.c",
            "deps/libvorbis-1.3.7/lib/info.c",
            "deps/libvorbis-1.3.7/lib/floor1.c",
            "deps/libvorbis-1.3.7/lib/floor0.c",
            "deps/libvorbis-1.3.7/lib/res0.c",
            "deps/libvorbis-1.3.7/lib/mapping0.c",
            "deps/libvorbis-1.3.7/lib/registry.c",
            "deps/libvorbis-1.3.7/lib/codebook.c",
            "deps/libvorbis-1.3.7/lib/sharedbook.c",
            "deps/libvorbis-1.3.7/lib/lookup.c",
            "deps/libvorbis-1.3.7/lib/bitrate.c",
            "deps/libvorbis-1.3.7/lib/vorbisfile.c",
            "deps/libvorbis-1.3.7/lib/vorbisenc.c",
        },
        &.{},
    );

    exe.addIncludePath("deps/glfw/glfw-3.3.8.bin.WIN64/include");

    exe.linkLibC();

    if (target.os_tag != null and target.os_tag.? == .windows) {
        exe.addLibraryPath("deps/glfw/glfw-3.3.8.bin.WIN64/lib-mingw-w64");
        exe.addLibraryPath("deps/openal-win/openal-soft-1.22.2-bin/libs/Win64");
        exe.linkSystemLibraryName("glfw3dll");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("OpenAL32");
    } else {
        exe.addLibraryPath("deps/openal-soft-1.22.2/build/");
        exe.linkSystemLibrary("glfw");
        exe.linkSystemLibrary("openal");
    }

    exe.addIncludePath("deps/openal-soft-1.22.2/include/");

    exe.disable_sanitize_c = true;
    exe.rdynamic = true;

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
