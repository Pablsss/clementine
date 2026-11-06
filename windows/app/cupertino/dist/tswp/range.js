import { ScriptPosition, Storage, StrikethruType, TSWP_TYPE, UnderlineType } from "./schema.js";
export class TextRange {
    storage;
    start;
    end;
    /** The storage revision this range's offsets were captured against. */
    revision;
    constructor(storage, start, end) {
        const len = storage.text.length;
        if (start < 0 || end < start || end > len) {
            throw new RangeError(`TextRange ${start}..${end} out of bounds (text length ${len})`);
        }
        this.storage = storage;
        this.start = start;
        this.end = end;
        this.revision = storage.revision;
    }
    /**
     * Captured offsets stay meaningful only while nothing before them moves.
     * Edits at or after `end` are fine — including the descending-order
     * idiom over one snapshot — but an edit before this range shifts the
     * text under it, and using the range then would silently hit the wrong
     * span. Loud is better.
     */
    assertFresh() {
        if (!this.storage.offsetsStableSince(this.revision, this.end)) {
            throw new RangeError(`stale TextRange ${this.start}..${this.end}: the storage was edited before this range ` +
                `after it was obtained — re-obtain offsets (find()/range()/paragraph()), or make ` +
                `multi-span changes through applyEdits(), which needs no ordering discipline`);
        }
    }
    get text() {
        this.assertFresh();
        return this.storage.text.slice(this.start, this.end);
    }
    /** Replace this range's text; returns the range covering the replacement. */
    replaceWith(text) {
        this.assertFresh();
        this.storage.replaceRange(this.start, this.end, text);
        return new TextRange(this.storage, this.start, this.start + text.length);
    }
    delete() {
        this.assertFresh();
        this.storage.deleteRange(this.start, this.end);
    }
    /**
     * Apply direct character formatting (one anonymous character style over
     * the range, parented on the style in effect at `start`). Prefer a single
     * call with all properties over chaining sugar methods — each call
     * creates one style object.
     */
    format(formatting) {
        this.assertFresh();
        const sheet = this.storage.sheet();
        if (!sheet)
            throw new RangeError("storage has no stylesheet; cannot create styles");
        const current = this.storage.effectiveObjectAt(Storage.TABLE_CHAR_STYLE, this.start);
        const styleId = sheet.createCharacterStyle({ basedOn: current, character: formatting });
        this.storage.setCharacterStyleRange(this.start, this.end, styleId);
        return this;
    }
    bold(value = true) {
        return this.format({ bold: value });
    }
    italic(value = true) {
        return this.format({ italic: value });
    }
    underline(value = true) {
        return this.format({ underline: value ? UnderlineType.SINGLE : UnderlineType.NONE });
    }
    fontSize(points) {
        return this.format({ fontSize: points });
    }
    fontName(postScriptName) {
        return this.format({ fontName: postScriptName });
    }
    color(r, g, b, a = 1) {
        return this.format({ fontColor: { r, g, b, a } });
    }
    /** Highlight colour drawn behind the glyphs. */
    highlight(color) {
        return this.format({ backgroundColor: color });
    }
    strikethrough(value = true) {
        return this.format({ strikethru: value ? StrikethruType.SINGLE : StrikethruType.NONE });
    }
    superscript() {
        return this.format({ superscript: ScriptPosition.SUPERSCRIPT });
    }
    subscript() {
        return this.format({ superscript: ScriptPosition.SUBSCRIPT });
    }
    /** Apply direct paragraph formatting to every paragraph in this range. */
    formatParagraphs(formatting) {
        for (const p of this.paragraphs())
            p.format(formatting);
        return this;
    }
    /** Apply a character style by name or id (undefined restores paragraph style). */
    applyCharacterStyle(style) {
        this.assertFresh();
        const id = style === undefined
            ? undefined
            : this.storage.resolveStyle(style, TSWP_TYPE.CHARACTER_STYLE);
        this.storage.setCharacterStyleRange(this.start, this.end, id);
        return this;
    }
    /** Apply a paragraph style to every paragraph intersecting this range. */
    applyParagraphStyle(style) {
        this.assertFresh();
        const id = this.storage.resolveStyle(style, TSWP_TYPE.PARAGRAPH_STYLE);
        for (const p of this.paragraphIndexes())
            this.storage.setParagraphStyle(p, id);
        return this;
    }
    /** Apply a list style (e.g. "Bullet", "Numbered", "None") to intersecting paragraphs. */
    applyListStyle(style) {
        this.assertFresh();
        const id = this.storage.resolveStyle(style, TSWP_TYPE.LIST_STYLE);
        for (const p of this.paragraphIndexes())
            this.storage.setListStyle(p, id);
        return this;
    }
    /** Make this range a hyperlink. */
    link(url) {
        this.assertFresh();
        this.storage.insertLink(this.start, this.end, url);
        return this;
    }
    /** Mark this range as template placeholder text (tap to replace). */
    asPlaceholder() {
        this.assertFresh();
        this.storage.defineAsPlaceholder(this.start, this.end);
        return this;
    }
    /** Remove hyperlinks overlapping this range. */
    unlink() {
        this.assertFresh();
        this.storage.removeLinks(this.start, this.end);
        return this;
    }
    paragraphIndexes() {
        this.assertFresh();
        const out = [];
        for (const p of this.storage.paragraphs()) {
            // A paragraph intersects if its span (including terminator position)
            // overlaps [start, end); a caret range at a boundary counts once.
            if (p.start < this.end && p.end >= this.start)
                out.push(p.index);
            else if (this.start === this.end && this.start >= p.start && this.start <= p.end) {
                out.push(p.index);
            }
        }
        return out;
    }
    paragraphs() {
        return this.paragraphIndexes().map((i) => new ParagraphHandle(this.storage, i));
    }
}
export class ParagraphHandle {
    storage;
    index;
    constructor(storage, index) {
        this.storage = storage;
        this.index = index;
    }
    info() {
        const p = this.storage.paragraphs()[this.index];
        if (!p)
            throw new RangeError(`paragraph ${this.index} no longer exists`);
        return p;
    }
    get text() {
        return this.info().text;
    }
    set text(value) {
        const p = this.info();
        this.storage.replaceRange(p.start, p.end, value);
    }
    /** Range covering the paragraph's text (excluding the terminator). */
    range() {
        const p = this.info();
        return new TextRange(this.storage, p.start, p.end);
    }
    get styleId() {
        return this.info().styleId;
    }
    /**
     * The named style this paragraph reads as — resolved through the
     * parent chain, so direct formatting does not hide it. This is the
     * name a table of contents collects by.
     */
    get styleName() {
        const id = this.styleId;
        return id !== undefined ? this.storage.styleNameOf(id) : undefined;
    }
    /**
     * True when the paragraph carries direct formatting: its style object
     * is the anonymous child {@link format} creates, rather than the named
     * style itself. {@link styleName} still names the style it inherits.
     */
    get hasDirectFormatting() {
        const id = this.styleId;
        return id !== undefined && this.storage.ownStyleNameOf(id) === undefined;
    }
    setStyle(style) {
        this.storage.setParagraphStyle(this.index, this.storage.resolveStyle(style, TSWP_TYPE.PARAGRAPH_STYLE));
        return this;
    }
    /**
     * Apply direct paragraph formatting: create an anonymous paragraph style
     * parented on the one currently in effect, and assign it to this paragraph
     * alone. Prefer editing a named style when the change should apply
     * everywhere that style is used.
     */
    format(formatting, character) {
        const sheet = this.storage.sheet();
        if (!sheet)
            throw new RangeError("storage has no stylesheet; cannot create styles");
        const options = { paragraph: formatting };
        const current = this.styleId;
        if (current !== undefined)
            options.basedOn = current;
        if (character)
            options.character = character;
        this.storage.setParagraphStyle(this.index, sheet.createParagraphStyle(options));
        return this;
    }
    /** Base writing direction — where "natural" resolves from the text. */
    get direction() {
        return this.storage.paragraphDirection(this.index);
    }
    /** Flip the paragraph's base direction, as the app's ⇄ control does. */
    setDirection(direction) {
        this.storage.setParagraphDirection(this.index, direction);
        return this;
    }
    get listStyleId() {
        return this.storage.listStyleIdAt(this.index);
    }
    get listStyleName() {
        const id = this.listStyleId;
        return id !== undefined ? this.storage.styleNameOf(id) : undefined;
    }
    setListStyle(style) {
        this.storage.setListStyle(this.index, this.storage.resolveStyle(style, TSWP_TYPE.LIST_STYLE));
        return this;
    }
    /** Delete the paragraph including its terminator. */
    delete() {
        const p = this.info();
        const text = this.storage.text;
        const end = p.end < text.length ? p.end + 1 : p.end;
        // Deleting the last unterminated paragraph also removes the preceding \n.
        const start = p.end >= text.length && p.start > 0 ? p.start - 1 : p.start;
        this.storage.deleteRange(start, end);
    }
    /** Insert a new paragraph after this one; returns its handle. */
    insertAfter(text, style) {
        if (text.includes("\n"))
            throw new RangeError("paragraph text must not contain \\n");
        const p = this.info();
        const full = this.storage.text;
        if (p.end >= full.length) {
            // Last paragraph: append via the terminator-convention-preserving path.
            const idx = this.storage.appendParagraph(text);
            const handle = new ParagraphHandle(this.storage, idx);
            if (style !== undefined)
                handle.setStyle(style);
            return handle;
        }
        this.storage.insertText(p.end + 1, `${text}\n`);
        const handle = new ParagraphHandle(this.storage, this.index + 1);
        if (style !== undefined)
            handle.setStyle(style);
        return handle;
    }
}
//# sourceMappingURL=range.js.map