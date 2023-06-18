const std = @import("std");
const ma = @import("./miniaudio.zig").ma;

const record = struct {
    const State = struct {
        file: std.os.File,
    };

    fn onData(device: [*c]ma.ma_device, pOut: ?*anyopaque, pIn: ?*const anyopaque, frames: u32) callconv(.C) void {
        _ = pOut;
        const state = @ptrCast(*State, @alignCast(@alignOf(State), device.*.pUserData));
        const in: []const u8 = @ptrCast([*]const u8, pIn)[0 .. frames * @sizeOf(f32)];
        state.file.writeAll(in) catch |err| {
            std.debug.print("onData write err {}\n", .{err});
            state.done.set();
        };
    }

    fn run(ctx: *ma.ma_context) !void {
        var state = State{
            .file = try std.fs.cwd().createFileZ("out.raw", .{ .truncate = true }),
            .done = .{},
        };
        defer state.file.close();

        var config = ma.ma_device_config_init(ma.ma_device_type_capture);
        config.capture.format = ma.ma_format_f32;
        config.capture.channels = 1;
        config.sampleRate = 44100;
        config.dataCallback = onData;
        config.pUserData = &state;

        var device: ma.ma_device = undefined;
        if (ma.ma_device_init(ctx, &config, &device) != ma.MA_SUCCESS) {
            std.debug.print("init fail\n", .{});
        }

        const stdout = std.io.getStdOut().writer();

        if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
            std.debug.print("ma_device_start fail\n", .{});
        }
        try stdout.print("recording...\n", .{});

        const stdin = std.io.getStdIn().reader();
        var buf: [1]u8 = undefined;
        try stdin.read(&buf);

        std.time.sleep(2 * 1000 * 1000 * 1000);
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
        config.sampleRate = 44100;
        config.dataCallback = onData;
        config.pUserData = &state;

        var device: ma.ma_device = undefined;
        if (ma.ma_device_init(ctx, &config, &device) != ma.MA_SUCCESS) {
            std.debug.print("init fail\n", .{});
        }

        const stdout = std.io.getStdOut().writer();

        if (ma.ma_device_start(&device) != ma.MA_SUCCESS) {
            std.debug.print("ma_device_start fail\n", .{});
        }
        try stdout.print("playing...\n", .{});
        state.done.wait();
        ma.ma_device_uninit(&device);
    }
};

pub fn main() !void {
    var ctx: ma.ma_context = undefined;
    if (ma.ma_context_init(null, 0, null, &ctx) != ma.MA_SUCCESS) {
        std.debug.print("init fail", .{});
    }
    //try record.run(&ctx);
    try playback.run(&ctx);
}

test "simple test" {}
