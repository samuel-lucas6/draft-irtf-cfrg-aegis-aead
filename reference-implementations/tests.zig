const std = @import("std");

const aegis128l = @import("aegis128l.zig");
const aegis128x = @import("aegis128x.zig");
const aegis256 = @import("aegis256.zig");
const aegis256x = @import("aegis256x.zig");

test {
    const aegis_variants = [_]type{
        aegis128l.Aegis128L,  aegis128l.Aegis128L_256,
        aegis128x.Aegis128X2, aegis128x.Aegis128X2_256,
        aegis128x.Aegis128X4, aegis128x.Aegis128X4_256,
        aegis256.Aegis256,    aegis256.Aegis256_256,
        aegis256x.Aegis256X2, aegis256x.Aegis256X2_256,
        aegis256x.Aegis256X4, aegis256x.Aegis256X4_256,
    };
    inline for (aegis_variants) |Aegis| {
        const key = [_]u8{0x01} ** Aegis.key_length;
        const nonce = [_]u8{0x02} ** Aegis.nonce_length;
        const ad = [_]u8{0x03} ** 1000;
        const msg = [_]u8{0x04} ** 1000;
        var msg2: [msg.len]u8 = undefined;
        var ct: [msg.len]u8 = undefined;
        const tag = Aegis.encrypt(&ct, &msg, &ad, key, nonce);
        try Aegis.decrypt(&msg2, &ct, tag, &ad, key, nonce);
        try std.testing.expectEqualSlices(u8, &msg, &msg2);
    }
}

test {
    const aegis_variants = [_]type{
        aegis128l.Aegis128L,  aegis128l.Aegis128L_256,
        aegis128x.Aegis128X2, aegis128x.Aegis128X2_256,
        aegis128x.Aegis128X4, aegis128x.Aegis128X4_256,
        aegis256.Aegis256,    aegis256.Aegis256_256,
        aegis256x.Aegis256X2, aegis256x.Aegis256X2_256,
        aegis256x.Aegis256X4, aegis256x.Aegis256X4_256,
    };
    inline for (aegis_variants) |Aegis| {
        const key = [_]u8{ 0x10, 0x01 } ++ [_]u8{0x00} ** (Aegis.key_length - 2);
        const nonce = [_]u8{ 0x10, 0x00, 0x02 } ++ [_]u8{0x00} ** (Aegis.nonce_length - 3);
        var msg: [35]u8 = undefined;
        for (&msg, 0..) |*byte, i| byte.* = @truncate(i);
        _ = Aegis.mac(&msg, key, nonce);
    }
}
