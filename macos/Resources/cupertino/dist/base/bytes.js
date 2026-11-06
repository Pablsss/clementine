/**
 * Small byte-level utilities and shared constants for the whole library.
 * Zero dependencies; works in Node and browsers.
 */
/**
 * Apple's reference date, 2001-01-01T00:00:00Z. Timestamps throughout the
 * format — cell dates, comment dates, plist dates — are seconds from this
 * epoch, not Unix's.
 */
export const APPLE_EPOCH_MS = Date.UTC(2001, 0, 1);
export const APPLE_EPOCH_SECONDS = APPLE_EPOCH_MS / 1000;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8");
export function utf8Encode(s) {
    return textEncoder.encode(s);
}
export function utf8Decode(b) {
    return textDecoder.decode(b);
}
export function concatBytes(chunks) {
    let total = 0;
    for (const c of chunks)
        total += c.length;
    const out = new Uint8Array(total);
    let pos = 0;
    for (const c of chunks) {
        out.set(c, pos);
        pos += c.length;
    }
    return out;
}
export function bytesEqual(a, b) {
    if (a === b)
        return true;
    if (a.length !== b.length)
        return false;
    for (let i = 0; i < a.length; i++)
        if (a[i] !== b[i])
            return false;
    return true;
}
/** Growable little-endian byte sink. */
export class ByteWriter {
    buf;
    len = 0;
    constructor(initialCapacity = 256) {
        this.buf = new Uint8Array(initialCapacity);
    }
    get length() {
        return this.len;
    }
    ensure(extra) {
        const need = this.len + extra;
        if (need <= this.buf.length)
            return;
        let cap = Math.max(this.buf.length * 2, 16);
        while (cap < need)
            cap *= 2;
        const next = new Uint8Array(cap);
        next.set(this.buf.subarray(0, this.len));
        this.buf = next;
    }
    byte(b) {
        this.ensure(1);
        this.buf[this.len++] = b & 0xff;
    }
    bytes(b) {
        this.ensure(b.length);
        this.buf.set(b, this.len);
        this.len += b.length;
    }
    u16le(v) {
        this.ensure(2);
        this.buf[this.len++] = v & 0xff;
        this.buf[this.len++] = (v >>> 8) & 0xff;
    }
    u32le(v) {
        this.ensure(4);
        this.buf[this.len++] = v & 0xff;
        this.buf[this.len++] = (v >>> 8) & 0xff;
        this.buf[this.len++] = (v >>> 16) & 0xff;
        this.buf[this.len++] = (v >>> 24) & 0xff;
    }
    u64le(v) {
        this.ensure(8);
        let x = BigInt.asUintN(64, v);
        for (let i = 0; i < 8; i++) {
            this.buf[this.len++] = Number(x & 0xffn);
            x >>= 8n;
        }
    }
    /** Copy of the written bytes. */
    toBytes() {
        return this.buf.slice(0, this.len);
    }
}
export function readU16le(b, pos) {
    return b[pos] | (b[pos + 1] << 8);
}
export function readU32le(b, pos) {
    return (b[pos] | (b[pos + 1] << 8) | (b[pos + 2] << 16) | (b[pos + 3] << 24)) >>> 0;
}
export function readU64le(b, pos) {
    let v = 0n;
    for (let i = 7; i >= 0; i--)
        v = (v << 8n) | BigInt(b[pos + i]);
    return v;
}
//# sourceMappingURL=bytes.js.map