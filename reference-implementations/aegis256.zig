const std = @import("std");
const assert = std.debug.assert;
const crypto = std.crypto;
const mem = std.mem;
const AesBlock = std.crypto.core.aes.Block;
const AuthenticationError = std.crypto.errors.AuthenticationError;

pub const Aegis256 = Aegis256_(128);
pub const Aegis256_256 = Aegis256_(256);

fn Aegis256_(comptime tag_bits: u9) type {
    assert(tag_bits == 128 or tag_bits == 256); // tag bits must be 128 or 256

    return struct {
        const Self = @This();

        pub const key_length = 32;
        pub const nonce_length = 32;
        pub const tag_length: comptime_int = tag_bits / 8;
        pub const ad_max_length = 1 << 61;
        pub const msg_max_length = 1 << 61;
        pub const ct_max_length = msg_max_length + tag_length;

        const State = [6]AesBlock;

        s: State,

        inline fn aesround(in: AesBlock, rk: AesBlock) AesBlock {
            return in.encrypt(rk);
        }

        fn update(self: *Self, m: AesBlock) void {
            const s = self.s;
            self.s = State{
                aesround(s[5], s[0].xorBlocks(m)),
                aesround(s[0], s[1]),
                aesround(s[1], s[2]),
                aesround(s[2], s[3]),
                aesround(s[3], s[4]),
                aesround(s[4], s[5]),
            };
        }

        fn init(key: [key_length]u8, nonce: [nonce_length]u8) Self {
            const c0 = AesBlock.fromBytes(&[16]u8{ 0x00, 0x01, 0x01, 0x02, 0x03, 0x05, 0x08, 0x0d, 0x15, 0x22, 0x37, 0x59, 0x90, 0xe9, 0x79, 0x62 });
            const c1 = AesBlock.fromBytes(&[16]u8{ 0xdb, 0x3d, 0x18, 0x55, 0x6d, 0xc2, 0x2f, 0xf1, 0x20, 0x11, 0x31, 0x42, 0x73, 0xb5, 0x28, 0xdd });
            const k0 = AesBlock.fromBytes(key[0..16]);
            const k1 = AesBlock.fromBytes(key[16..32]);
            const n0 = AesBlock.fromBytes(nonce[0..16]);
            const n1 = AesBlock.fromBytes(nonce[16..32]);
            var self = Self{ .s = State{
                k0.xorBlocks(n0),
                k1.xorBlocks(n1),
                c1,
                c0,
                k0.xorBlocks(c0),
                k1.xorBlocks(c1),
            } };
            for (0..4) |_| {
                self.update(k0);
                self.update(k1);
                self.update(k0.xorBlocks(n0));
                self.update(k1.xorBlocks(n1));
            }
            return self;
        }

        fn absorb(self: *Self, ai: *const [16]u8) void {
            const t = AesBlock.fromBytes(ai);
            self.update(t);
        }

        fn enc(self: *Self, xi: *const [16]u8) [16]u8 {
            const s = self.s;
            const z = s[1].xorBlocks(s[4]).xorBlocks(s[5]).xorBlocks(s[2].andBlocks(s[3]));
            const t = AesBlock.fromBytes(xi);
            const ci = t.xorBlocks(z);
            self.update(t);
            return ci.toBytes();
        }

        fn dec(self: *Self, ci: *const [16]u8) [16]u8 {
            const s = self.s;
            const z = s[1].xorBlocks(s[4]).xorBlocks(s[5]).xorBlocks(s[2].andBlocks(s[3]));
            const t = AesBlock.fromBytes(ci);
            const xi = t.xorBlocks(z);
            self.update(xi);
            return xi.toBytes();
        }

        fn decLast(self: *Self, xn: []u8, cn: []const u8) void {
            const s = self.s;
            const z = s[1].xorBlocks(s[4]).xorBlocks(s[5]).xorBlocks(s[2].andBlocks(s[3]));
            var pad = [_]u8{0} ** 16;
            @memcpy(pad[0..cn.len], cn);
            const t = AesBlock.fromBytes(&pad);
            const out = t.xorBlocks(z);
            pad = out.toBytes();
            @memcpy(xn, pad[0..cn.len]);
            @memset(pad[cn.len..], 0);
            const v = AesBlock.fromBytes(&pad);
            self.update(v);
        }

        fn finalize(self: *Self, ad_len: usize, msg_len: usize) [tag_length]u8 {
            var s = &self.s;
            var b: [16]u8 = undefined;
            mem.writeInt(u64, b[0..8], @as(u64, ad_len) * 8, .little);
            mem.writeInt(u64, b[8..16], @as(u64, msg_len) * 8, .little);
            const t = s[3].xorBlocks(AesBlock.fromBytes(&b));
            for (0..7) |_| {
                self.update(t);
            }
            var tag: [tag_length]u8 = undefined;
            if (tag_length == 16) {
                tag = s[0].xorBlocks(s[1]).xorBlocks(s[2]).xorBlocks(s[3]).xorBlocks(s[4]).xorBlocks(s[5]).toBytes();
            } else {
                tag[0..16].* = s[0].xorBlocks(s[1]).xorBlocks(s[2]).toBytes();
                tag[16..].* = s[3].xorBlocks(s[4]).xorBlocks(s[5]).toBytes();
            }
            return tag;
        }

        pub fn encrypt(
            ct: []u8,
            msg: []const u8,
            ad: []const u8,
            key: [key_length]u8,
            nonce: [nonce_length]u8,
        ) [tag_length]u8 {
            assert(msg.len <= msg_max_length);
            assert(ad.len <= ad_max_length);
            assert(ct.len == msg.len);
            var aegis = init(key, nonce);

            var i: usize = 0;
            while (i + 16 <= ad.len) : (i += 16) {
                aegis.absorb(ad[i..][0..16]);
            }
            if (ad.len % 16 != 0) {
                var pad = [_]u8{0} ** 16;
                @memcpy(pad[0 .. ad.len % 16], ad[i..]);
                aegis.absorb(&pad);
            }

            i = 0;
            while (i + 16 <= msg.len) : (i += 16) {
                ct[i..][0..16].* = aegis.enc(msg[i..][0..16]);
            }
            if (msg.len % 16 != 0) {
                var pad = [_]u8{0} ** 16;
                @memcpy(pad[0 .. msg.len % 16], msg[i..]);
                @memcpy(ct[i..], aegis.enc(&pad)[0 .. msg.len % 16]);
            }

            return aegis.finalize(ad.len, msg.len);
        }

        pub fn decrypt(
            msg: []u8,
            ct: []const u8,
            tag: [tag_length]u8,
            ad: []const u8,
            key: [key_length]u8,
            nonce: [nonce_length]u8,
        ) AuthenticationError!void {
            assert(ct.len <= ct_max_length);
            assert(ad.len <= ad_max_length);
            assert(ct.len == msg.len);
            var aegis = init(key, nonce);

            var i: usize = 0;
            while (i + 16 <= ad.len) : (i += 16) {
                aegis.absorb(ad[i..][0..16]);
            }
            if (ad.len % 16 != 0) {
                var pad = [_]u8{0} ** 16;
                @memcpy(pad[0 .. ad.len % 16], ad[i..]);
                aegis.absorb(&pad);
            }

            i = 0;
            while (i + 16 <= ct.len) : (i += 16) {
                msg[i..][0..16].* = aegis.dec(ct[i..][0..16]);
            }
            if (ct.len % 16 != 0) {
                aegis.decLast(msg[i..], ct[i..]);
            }

            const expected_tag = aegis.finalize(ad.len, msg.len);
            if (!crypto.utils.timingSafeEql([expected_tag.len]u8, expected_tag, tag)) {
                crypto.utils.secureZero(u8, msg);
                return error.AuthenticationFailed;
            }
        }

        pub fn stream(
            out: []u8,
            key: [key_length]u8,
            nonce: ?[nonce_length]u8,
        ) void {
            assert(out.len <= msg_max_length);
            var aegis = init(key, nonce orelse [_]u8{0} ** nonce_length);

            const zero = [_]u8{0} ** 16;

            var i: usize = 0;
            while (i + 16 <= out.len) : (i += 16) {
                out[i..][0..16].* = aegis.enc(&zero);
            }
            if (out.len % 16 != 0) {
                @memcpy(out[i..], aegis.enc(&zero)[0 .. out.len % 16]);
            }
        }

        pub fn mac(
            data: []const u8,
            key: [key_length]u8,
            nonce: [nonce_length]u8,
        ) [tag_length]u8 {
            assert(data.len <= ad_max_length);
            var aegis = init(key, nonce);

            var i: usize = 0;
            while (i + 16 <= data.len) : (i += 16) {
                aegis.absorb(data[i..][0..16]);
            }
            if (data.len % 16 != 0) {
                var pad = [_]u8{0} ** 16;
                @memcpy(pad[0 .. data.len % 16], data[i..]);
                aegis.absorb(&pad);
            }
            return aegis.finalize(data.len, tag_length);
        }
    };
}
