import { WireType } from "../base/protobuf.js";
/**
 * Check a message against its schema, recursively.
 *
 * `messageName` is the fully-qualified name the message is expected to
 * conform to. Submessages are followed only where the field's declared type
 * resolves, and only where the field is actually present — an absent
 * *optional* submessage cannot be missing anything.
 */
export function missingRequired(message, messageName, schema, path = messageName, depth = 0) {
    const definition = schema.get(messageName);
    if (!definition || depth > 12)
        return [];
    const out = [];
    for (const field of definition.values()) {
        const present = message.has(field.number);
        if (field.label === "required" && !present) {
            out.push({ path, message: messageName, field: field.name, number: field.number });
            continue;
        }
        if (!present || !schema.has(field.type))
            continue;
        // Only walk fields actually encoded as submessages: a field declared as
        // a message but written with another wire type is a different problem,
        // and getMessages would throw on it.
        if (!message.fields.some((f) => f.no === field.number && f.wire === WireType.Bytes)) {
            continue;
        }
        let children = [];
        try {
            children = message.getMessages(field.number);
        }
        catch {
            continue;
        }
        children.forEach((child, index) => {
            const suffix = children.length > 1 ? `[${index}]` : "";
            out.push(...missingRequired(child, field.type, schema, `${path}.${field.name}${suffix}`, depth + 1));
        });
    }
    return out;
}
//# sourceMappingURL=required.js.map