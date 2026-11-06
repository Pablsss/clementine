/** Read an unsigned varint (up to 64 bits) as a bigint. */
export function readUvarint(buf, pos) {
    // Fast path: values fitting in 4 bytes (28 bits) avoid BigInt arithmetic.
    let b = buf[pos];
    if (b === undefined)
        throw new RangeError("varint: unexpected end of input");
    if ((b & 0x80) === 0)
        return { value: BigInt(b), next: pos + 1 };
    let shift = 0;
    let low = 0;
    let p = pos;
    while (shift < 28) {
        b = buf[p];
        if (b === undefined)
            throw new RangeError("varint: unexpected end of input");
        p++;
        low |= (b & 0x7f) << shift;
        if ((b & 0x80) === 0)
            return { value: BigInt(low >>> 0), next: p };
        shift += 7;
    }
    // Slow path for values >= 2^28.
    let value = BigInt(low >>> 0);
    let bshift = 28n;
    for (let i = 0; i < 6; i++) {
        b = buf[p];
        if (b === undefined)
            throw new RangeError("varint: unexpected end of input");
        p++;
        value |= BigInt(b & 0x7f) << bshift;
        if ((b & 0x80) === 0)
            return { value: BigInt.asUintN(64, value), next: p };
        bshift += 7n;
    }
    throw new RangeError("varint: too long (more than 10 bytes)");
}
/** Read an unsigned varint expected to fit a JS number (< 2^53). */
export function readUvarintNumber(buf, pos) {
    const { value, next } = readUvarint(buf, pos);
    if (value > BigInt(Number.MAX_SAFE_INTEGER)) {
        throw new RangeError(`varint: value ${value} exceeds MAX_SAFE_INTEGER`);
    }
    return { value: Number(value), next };
}
export function writeUvarint(w, v) {
    let x = typeof v === "bigint" ? BigInt.asUintN(64, v) : BigInt(v);
    if (x < 0n)
        throw new RangeError("varint: negative value");
    while (x >= 0x80n) {
        w.byte(Number(x & 0x7fn) | 0x80);
        x >>= 7n;
    }
    w.byte(Number(x));
}
export function uvarintLength(v) {
    let x = typeof v === "bigint" ? BigInt.asUintN(64, v) : BigInt(v);
    let n = 1;
    while (x >= 0x80n) {
        x >>= 7n;
        n++;
    }
    return n;
}
/** ZigZag encoding used by protobuf sint32/sint64 fields. */
export function zigzagDecode(v) {
    return (v >> 1n) ^ -(v & 1n);
}
export function zigzagEncode(v) {
    return BigInt.asUintN(64, (v << 1n) ^ (v >> 63n));
}
//# sourceMappingURL=varint.js.map