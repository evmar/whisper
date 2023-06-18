const std = @import("std");
const ma = @import("./miniaudio.zig").ma;
const whisper = @cImport(@cInclude("whisper.h"));

var stdout: @TypeOf(std.io.getStdOut().writer()) = undefined;
const SAMPLE_RATE = 16000;

const record = struct {
    const State = struct {
        file: std.fs.File,
    };

    fn onData(device: [*c]ma.ma_device, pOut: ?*anyopaque, pIn: ?*const anyopaque, frames: u32) callconv(.C) void {
        _ = pOut;
        const state = @ptrCast(*State, @alignCast(@alignOf(State), device.*.pUserData));
        const in: []const u8 = @ptrCast([*]const u8, pIn)[0 .. frames * @sizeOf(f32)];
        state.file.writeAll(in) catch |err| {
            std.debug.print("onData write err {}\n", .{err});
        };
    }

    fn run(ctx: *ma.ma_context) !void {
        var state = State{
            .file = try std.fs.cwd().createFileZ("out.raw", .{ .truncate = true }),
        };
        defer state.file.close();

        var config = ma.ma_device_config_init(ma.ma_device_type_capture);
        config.capture.format = ma.ma_format_f32;
        config.capture.channels = 1;
        config.sampleRate = SAMPLE_RATE;
        config.dataCallback = onData;
        config.pUserData = &state;

        var device: ma.ma_device = undefined;
        if (ma.ma_device_init(ctx, &config, &device) != ma.MA_SUCCESS) {
            std.debug.print("init fail\n", .{});
        }

        if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
            std.debug.print("ma_device_start fail\n", .{});
        }
        try stdout.print("recording...\n", .{});

        const stdin = std.io.getStdIn().reader();
        var buf: [1]u8 = undefined;
        _ = try stdin.read(&buf);

        ma.ma_device_uninit(&device);
    }
};

const playback = struct {
    const State = struct {
        file: std.fs.File,
        done: std.Thread.ResetEvent,
    };

    fn onData(device: [*c]ma.ma_device, pOut: ?*anyopaque, pIn: ?*const anyopaque, frames: u32) callconv(.C) void {
        _ = pIn;
        const state = @ptrCast(*State, @alignCast(@alignOf(State), device.*.pUserData));
        const out: []u8 = @ptrCast([*]u8, pOut)[0 .. frames * @sizeOf(f32)];

        const len = state.file.readAll(out) catch 0;
        if (len < out.len) {
            state.done.set();
        }
    }

    fn run(ctx: *ma.ma_context) !void {
        var state = State{
            .file = try std.fs.cwd().openFileZ("out.raw", .{}),
            .done = .{},
        };
        defer state.file.close();

        var config = ma.ma_device_config_init(ma.ma_device_type_playback);
        config.playback.format = ma.ma_format_f32;
        config.playback.channels = 1;
        config.sampleRate = SAMPLE_RATE;
        config.dataCallback = onData;
        config.pUserData = &state;

        var device: ma.ma_device = undefined;
        if (ma.ma_device_init(ctx, &config, &device) != ma.MA_SUCCESS) {
            std.debug.print("init fail\n", .{});
        }

        if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
            std.debug.print("ma_device_start fail\n", .{});
        }
        try stdout.print("playing...\n", .{});
        state.done.wait();
        ma.ma_device_uninit(&device);
    }
};

const model_path = "../whisper.cpp/models/ggml-small.en.bin";

fn transcribe() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var file = try std.fs.cwd().openFileZ("out.raw", .{});
    defer file.close();
    const buf = try file.readToEndAlloc(alloc, 10 << 20);

    var ctx = whisper.whisper_init_from_file(model_path);
    defer whisper.whisper_free(ctx);

    var params = whisper.whisper_full_default_params(whisper.WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    if (whisper.whisper_full(ctx, params, @ptrCast([*c]const f32, @alignCast(@alignOf(f32), buf.ptr)), @intCast(c_int, buf.len / 4)) != 0) {
        std.debug.panic("whisper failed", .{});
    }

    const segs = @intCast(usize, whisper.whisper_full_n_segments(ctx));
    for (0..segs) |i| {
        const text = whisper.whisper_full_get_segment_text(ctx, @intCast(c_int, i));
        try stdout.print("{} {s}\n", .{ i, text });
    }
}

pub fn main() !void {
    stdout = std.io.getStdOut().writer();

    var ctx: ma.ma_context = undefined;
    if (ma.ma_context_init(null, 0, null, &ctx) != ma.MA_SUCCESS) {
        std.debug.print("init fail", .{});
    }
    try record.run(&ctx);
    // try playback.run(&ctx);
    try transcribe();
}
