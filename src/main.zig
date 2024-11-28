const std = @import("std");
const CPU = @import("cpu.zig");
const Bus = @import("bus.zig").Bus;
const PPU = @import("ppu.zig").PPU;
const clap = @import("clap");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("time.h");
});

const memory_size = 0xffff;
const EmulatorState = enum(u4) { Init, Running, Paused, Quit };

fn peek_mem_adder(memory: *[memory_size]u8, adder: u16) u8 {
    return memory[adder];
}

const NES = struct {
    state: EmulatorState,
    master_clock: u64,
    cpu: CPU.CPU,
    bus: *Bus,
    ppu: *PPU,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help     Display this help and exit.
        \\-v, --version  Output version information and exit.
        \\
    );

    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = gpa.allocator(),
    });
    defer res.deinit();
    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }
    var memory: [memory_size]u8 = undefined;
    @memset(&memory, 0);
    const result = sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING);
    defer sdl.SDL_Quit();
    std.debug.print("result {}\n", .{result});

    const screen = sdl.SDL_CreateWindow("My Window", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, 400, 400, sdl.SDL_WINDOW_OPENGL);
    defer sdl.SDL_DestroyWindow(screen);

    var ppu = PPU.init();
    var bus = Bus.init(&ppu);
    var system = NES{
        .state = EmulatorState.Init,
        .master_clock = 0,
        .cpu = CPU.CPU.init(),
        .bus = &bus,
        .ppu = &ppu,
    };
    system.cpu.reset(system.bus);
    std.debug.print("status: {}\n", .{system.cpu.status});
    var cyclesLeft: i16 = 2;
    system.cpu.execute(&cyclesLeft, system.bus);
    std.debug.print("acumulator: {} status: {}\n", .{ system.cpu.accumulator, system.cpu.status });

    std.debug.print("made it through\n", .{});
    while (system.state != EmulatorState.Quit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    system.state = EmulatorState.Quit;
                },
                else => {},
            }
        }

        sdl.SDL_Delay(17);
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
