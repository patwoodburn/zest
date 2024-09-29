pub const PPU = struct {
    ppu_bus: [1024]u8,
    ppuctl: u8,
    ppumask: u8,
    ppustatus: u8,
    oamaddr: u8,
    oamdata: u8,
    ppuscroll: u8,
    ppuaddr: u8,
    ppudata: u8,
    oamdma: u8,

    pub fn init() PPU {
        var ppu = PPU{
            .ppu_bus = undefined,
            .ppuctl = 0x00,
            .ppumask = 0x00,
            .ppustatus = 0x00,
            .oamaddr = 0x00,
            .oamdata = 0x00,
            .ppuscroll = 0x00,
            .ppuaddr = 0x00,
            .ppudata = 0x00,
            .oamdma = 0x00,
        };
        @memset(&ppu.ppu_bus, 0);
        return ppu;
    }

    fn put(ppu: *PPU, adder: u16, value: u8) void {
        switch (adder) {
            0x2000 => {
                ppu.ppuctl = value;
            },
            0x2001 => {
                ppu.ppumask = value;
            },
            0x2002 => {
                ppu.ppustatus = value;
            },
            0x2003 => {
                ppu.oamaddr = value;
            },
            0x2004 => {
                ppu.oamdata = value;
            },
            0x2005 => {
                ppu.ppuscroll = value;
            },
            0x2006 => {
                ppu.ppudata = value;
            },
            0x2007 => {
                ppu.oamdma = value;
            },
            else => {
                unreachable;
            },
        }
    }

    fn fetch(_: PPU) u8 {
        return 0;
    }

    fn write(_: PPU) u8 {
        return 0;
    }
};
