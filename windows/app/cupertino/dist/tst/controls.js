/**
 * Cell controls (`TST.CellSpecArchive`) — Numbers' data-entry widgets.
 *
 * A cell can carry a control instead of a plain editing caret: a checkbox,
 * a star rating, a slider, a stepper, or a pop-up menu. The control lives
 * in `DataStore.control_cell_spec_table`, interned by key exactly like
 * strings and formats, and a cell's record points at it through the
 * `CONTROL_ID` field (flag `0x400`).
 *
 * ```proto
 * message TST.CellSpecArchive {
 *   required uint32 interaction_type = 1;
 *   optional TSCE.FormulaArchive formula = 2;
 *   optional double range_control_min = 3;
 *   optional double range_control_max = 4;
 *   optional double range_control_inc = 5;
 *   optional TSP.Reference chooser_control_popup_model = 6;
 *   optional bool chooser_control_start_w_first = 7;
 * }
 * ```
 *
 * `interaction_type` is an enum Apple never published, and it is known —
 * measured, not guessed, from documents that put one widget per row and
 * say in their own cell values which row is which. See
 * {@link InteractionType} for the evidence behind each name.
 *
 * {@link controlShape} does not lean on the enum: it reports what the
 * archive *demonstrably contains* — min/max/increment, or a popup
 * model — independently of it. A file from a future Numbers with a
 * sixth widget will still classify as a range or a chooser, which is a
 * better answer than an unrecognised number.
 */
import { measuredEnum, protoFields } from "../proto/fields.js";
import { RawMessage } from "../base/protobuf.js";
import { refId } from "../tsp/schema.js";
/** TST.DataStore.control_cell_spec_table. */
export const CONTROL_CELL_SPEC_TABLE = 21;
/** TST.CellSpecArchive. */
export const CellSpecFields = protoFields("TST.CellSpecArchive", {
    INTERACTION_TYPE: "interaction_type",
    FORMULA: "formula",
    RANGE_MIN: "range_control_min",
    RANGE_MAX: "range_control_max",
    RANGE_INCREMENT: "range_control_inc",
    CHOOSER_POPUP_MODEL: "chooser_control_popup_model",
    CHOOSER_START_WITH_FIRST: "chooser_control_start_w_first",
});
/**
 * `TST.CellSpecArchive.interaction_type`.
 *
 * Apple publishes no enum. These names come from documents that lay one
 * widget out per row and state in their own cell values which row is which:
 *
 *  - **8 — checkbox.** Its row holds `FALSE` and `TRUE`, and its spec is a
 *    lone `interaction_type` with nothing to configure.
 *  - **6 — star rating.** Bounded `[0…5]` step 1 in every instance, with
 *    values 0, 3 and 5 in the row beneath.
 *  - **5 — slider.** One instance is `[1…50]` step 0.1, matching a
 *    published test that builds exactly that cell as a slider.
 *  - **4 — stepper.** The remaining range widget; Numbers offers five
 *    controls in total and the other four are accounted for.
 *  - **7 — pop-up menu.** The only one carrying a chooser popup model.
 *
 * The 4/5 pairing is the one a file cannot settle — a stepper and a slider
 * store the identical field set, so nothing in a file separates them. The
 * assignment is **observed** in the app instead: a document authoring one
 * of each was opened in Numbers and both drew as labelled.
 *
 * Values outside this set are carried through untouched rather than
 * rejected — see {@link controlShape}, which classifies by contents.
 */
export const InteractionType = measuredEnum("TST.CellSpecArchive.interaction_type", {
    STEPPER: 4,
    SLIDER: 5,
    STAR_RATING: 6,
    POPUP_MENU: 7,
    CHECKBOX: 8,
}, "There is no enum to look up: `interaction_type` is a plain uint32 in " +
    "TSTArchives.proto. Every value here was established in the app — a " +
    "document authoring one control of each kind was opened in Numbers and " +
    "each drew as labelled, which is also what separated 4 from 5.");
/** Display names for {@link InteractionType}; `undefined` when unrecognised. */
export const INTERACTION_TYPE_NAMES = new Map([
    [InteractionType.STEPPER, "stepper"],
    [InteractionType.SLIDER, "slider"],
    [InteractionType.STAR_RATING, "star rating"],
    [InteractionType.POPUP_MENU, "pop-up menu"],
    [InteractionType.CHECKBOX, "checkbox"],
]);
/** Classify a spec by what it actually carries. */
export function controlShape(spec) {
    if (spec.has(CellSpecFields.CHOOSER_POPUP_MODEL))
        return "chooser";
    if (spec.has(CellSpecFields.RANGE_MIN) ||
        spec.has(CellSpecFields.RANGE_MAX) ||
        spec.has(CellSpecFields.RANGE_INCREMENT)) {
        return "range";
    }
    if (spec.has(CellSpecFields.FORMULA))
        return "formula";
    return "toggle";
}
/** Read one `TST.CellSpecArchive`. */
export function readCellSpec(spec, key) {
    const interactionType = spec.getUint(CellSpecFields.INTERACTION_TYPE);
    return {
        key,
        interactionType,
        widget: interactionType === undefined ? undefined : INTERACTION_TYPE_NAMES.get(interactionType),
        shape: controlShape(spec),
        minimum: spec.getDouble(CellSpecFields.RANGE_MIN),
        maximum: spec.getDouble(CellSpecFields.RANGE_MAX),
        increment: spec.getDouble(CellSpecFields.RANGE_INCREMENT),
        popupModelId: refId(spec, CellSpecFields.CHOOSER_POPUP_MODEL),
        startsWithFirstItem: spec.getBool(CellSpecFields.CHOOSER_START_WITH_FIRST),
        hasFormula: spec.has(CellSpecFields.FORMULA),
        populatedFields: [...new Set(spec.fields.map((field) => field.no))].sort((a, b) => a - b),
    };
}
/**
 * TST.TableDataList / .ListEntry, as used by the control-spec table.
 *
 * `CELL_SPEC` is field 12, read off real documents. A reader that has to
 * guess the field needs a heuristic that skips any single-varint
 * submessage so a bare `TSP.Reference` is not misread as a control — and
 * that heuristic silently drops every checkbox, whose whole spec *is* one
 * varint. Knowing the field number removes the need to guess and the bug
 * with it.
 */
const DataList = { ENTRIES: 3 };
const ListEntry = { KEY: 1, CELL_SPEC: 12 };
/**
 * Every control a table interns, by key.
 *
 * Field 12 first, then a scan of the entry's other submessages so a layout
 * from another Numbers version still decodes rather than yielding nothing.
 */
export function controlsOf(store, dataStore) {
    const list = store.resolve(refId(dataStore, CONTROL_CELL_SPEC_TABLE));
    return list ? readControlList(list.message) : new Map();
}
/**
 * Decode a control-spec `TST.TableDataList`.
 *
 * Split out from {@link controlsOf} so the entry-unwrapping — the part
 * where a wrong guess silently drops checkboxes — can be exercised without
 * a document around it.
 */
export function readControlList(list) {
    const out = new Map();
    for (const entry of list.getMessages(DataList.ENTRIES)) {
        const key = entry.getUint(ListEntry.KEY);
        if (key === undefined)
            continue;
        const spec = specAt(entry, ListEntry.CELL_SPEC) ?? readSpecMessage(entry);
        if (spec)
            out.set(key, readCellSpec(spec, key));
    }
    return out;
}
/** The spec at a known field, if the entry carries one there. */
function specAt(entry, field) {
    let sub;
    try {
        sub = entry.getMessage(field);
    }
    catch {
        return undefined;
    }
    return sub?.has(CellSpecFields.INTERACTION_TYPE) ? sub : undefined;
}
/**
 * Fallback: the spec inside a list entry at some other field.
 *
 * Only reached when field 12 holds nothing. The single-varint guard lives
 * here — at an unknown field a lone varint really could be a reference —
 * and it does not cost checkboxes, which {@link specAt} finds first.
 */
function readSpecMessage(entry) {
    for (const field of entry.fields) {
        if (field.wire !== 2)
            continue;
        let sub;
        try {
            sub = entry.getMessage(field.no);
        }
        catch {
            continue;
        }
        if (!sub)
            continue;
        // A spec always states its interaction type; a bare reference is one
        // varint at field 1 and would be misread as a type-1 control.
        if (sub.fields.length === 1 && sub.fields[0].no === 1 && sub.fields[0].wire === 0) {
            continue;
        }
        if (sub.has(CellSpecFields.INTERACTION_TYPE))
            return sub;
    }
    return undefined;
}
/** `TST.PopUpMenuModel`, the archive holding a menu's list of choices. */
export const PopUpMenuModelFields = protoFields("TST.PopUpMenuModel", {
    /** `repeated CellValue item` — Apple marks this deprecated. */
    LEGACY_ITEM: "item",
    /**
     * `repeated TSCE.CellValueArchive tsce_item` — the live one.
     *
     * Named for the proto field rather than for what it holds, because
     * `proto:check` matches constants to schema fields *by name*: called
     * `ITEM` it matched `item = 1` and reported permanent drift against a
     * field number three verified menus in Numbers say is right.
     */
    TSCE_ITEM: "tsce_item",
});
/** `TSCE.CellValueArchive`. */
const CellValueFields = { TYPE: 1, BOOLEAN: 2, DATE: 3, NUMBER: 4, STRING: 5 };
/** `TSCE.CellValueArchive.CellValueType`. */
const CellValueType = { NIL: 1, BOOLEAN: 2, DATE: 3, NUMBER: 4, STRING: 5 };
/**
 * `TSK.FormatStructArchive.format_type` for the two kinds of item a menu
 * holds. Same codes the cell formats use — 260 text, 256 plain number.
 */
const ITEM_FORMAT_TYPE = { STRING: 260, NUMBER: 256 };
/**
 * The reserved slot every menu model begins with.
 *
 * `tsce_item[0]` is **not a choice** — it is the menu's "None" entry, and it
 * holds a `NIL_TYPE` value. This was measured, and the measurement is worth
 * keeping because the symptom is so quiet: a model written as a plain list
 * of choices opens cleanly, draws a working menu, and silently offers one
 * fewer item than it was given. `[Apple, Pear, Quince]` yields Pear and
 * Quince.
 *
 * Three readings fit that evidence and one document each separated them:
 *
 *  - Turning `chooser_control_start_w_first` off did not restore the item.
 *    It added a visible "none" row above Pear and Quince — so that flag
 *    governs whether the None entry is *offered*, not whether it exists.
 *  - A leading `NIL_TYPE` restored all three choices with the right one
 *    selected. This is the answer.
 *  - A leading *copy of the selected value* also restored all three
 *    choices, but the menu then marked none of them as current — Pear was
 *    listed without its checkmark. Occupying slot 0 with a real value fixes
 *    the count and breaks the selection, which is what rules out "slot 0
 *    holds the selection" and leaves only "slot 0 is the None entry".
 *
 * Slot 0 is therefore always the NIL entry below — measured, settled.
 */
/**
 * Build a `TST.PopUpMenuModel` from a list of choices.
 *
 * ```proto
 * message TST.PopUpMenuModel {
 *   repeated CellValue item = 1 [deprecated = true];
 *   repeated TSCE.CellValueArchive tsce_item = 2;
 * }
 * ```
 *
 * Each item is a `TSCE.CellValueArchive`, and the trap is one level down:
 * both `StringCellValueArchive.format` and `NumberCellValueArchive.format`
 * are `required`, so an item without one is a malformed message and takes
 * the whole document with it. `TSK.FormatStructArchive` has no required
 * fields of its own, but `format_type` is written anyway — an empty format
 * is *valid* and says nothing, and valid-but-empty is the shape that
 * leaves a widget undrawn.
 *
 * The deprecated `item` field is left off. It is Apple's own older shape
 * and nothing in the current schema requires both.
 *
 * **Unverified.** No document available here contains a pop-up menu, so
 * this is built from the schema rather than measured against one, and
 * schema-correct is not the same as working — a control with no format is
 * flawless on paper and invisible in the app. Treat a menu as unproven
 * until someone opens one.
 */
/**
 * The reserved-slot marker. A symbol, not a string sentinel: menu items are
 * strings, so an in-band marker like `"nil"` would silently turn a
 * legitimate choice with that exact text into the None slot.
 */
const NIL_SLOT = Symbol("popup none slot");
export function buildPopupMenuModel(items) {
    if (items.length === 0)
        throw new RangeError("a pop-up menu needs at least one item");
    const model = RawMessage.create();
    // Slot 0 first, always — see the measurement above. Without it the menu
    // loses whichever choice happens to be written first.
    const entries = [NIL_SLOT, ...items];
    model.setMessages(PopUpMenuModelFields.TSCE_ITEM, entries.map((item) => {
        const value = RawMessage.create();
        if (item === NIL_SLOT) {
            // A NIL_TYPE value carries no body at all — the type is the whole
            // message, and every value field is optional.
            value.setVarint(CellValueFields.TYPE, CellValueType.NIL);
            return value;
        }
        const format = RawMessage.create();
        const body = RawMessage.create();
        if (typeof item === "string") {
            value.setVarint(CellValueFields.TYPE, CellValueType.STRING);
            format.setVarint(1, ITEM_FORMAT_TYPE.STRING);
            body.setString(1, item);
            body.setMessage(2, format); // required
            value.setMessage(CellValueFields.STRING, body);
        }
        else {
            if (!Number.isFinite(item))
                throw new RangeError(`menu item is not finite: ${item}`);
            value.setVarint(CellValueFields.TYPE, CellValueType.NUMBER);
            format.setVarint(1, ITEM_FORMAT_TYPE.NUMBER);
            body.setDouble(1, item);
            body.setMessage(3, format); // required, and field 3 here, not 2
            value.setMessage(CellValueFields.NUMBER, body);
        }
        return value;
    }));
    return model;
}
/**
 * Read a `TST.PopUpMenuModel` back into its list of choices.
 *
 * A `NIL_TYPE` entry is skipped rather than reported. Numbers appears to
 * treat slot 0 as something other than a choice — a plain three-item model
 * offers only two in the app — so a nil there is structural, not an item
 * somebody meant to put in the menu.
 */
export function readPopupMenuModel(model) {
    if (!model)
        return [];
    const out = [];
    for (const value of model.getMessages(PopUpMenuModelFields.TSCE_ITEM)) {
        switch (value.getUint(CellValueFields.TYPE)) {
            case CellValueType.STRING: {
                const s = value.getMessage(CellValueFields.STRING)?.getString(1);
                if (s !== undefined)
                    out.push(s);
                break;
            }
            case CellValueType.NUMBER: {
                const n = value.getMessage(CellValueFields.NUMBER)?.getDouble(1);
                if (n !== undefined)
                    out.push(n);
                break;
            }
            default:
                break;
        }
    }
    return out;
}
//# sourceMappingURL=controls.js.map