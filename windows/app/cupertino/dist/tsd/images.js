/**
 * TSD.ImageArchive — images placed in any iWork document, including the
 * "image filters" Pages/Keynote/Numbers expose in the Adjust Image panel
 * (`TSD.ImageAdjustmentsArchive`) and instant-alpha/shape masks.
 *
 * Adjustments are plain scalars stored alongside the original media, so
 * they are safe to read *and* write: the apps re-render from the untouched
 * source bytes plus these parameters.
 */
import { protoFields } from "../proto/fields.js";
import { RawMessage } from "../base/protobuf.js";
import { makeRef, refId, SizeFields } from "../tsp/schema.js";
import { DrawableModel } from "./drawables.js";
import { Drawable, Image, TSD_TYPE } from "./schema.js";
import { buildRectangularMask, MaskModel } from "./masks.js";
/** TSD.ImageArchive: imageAdjustments = 14, plus the media variants. */
const IMAGE_ADJUSTMENTS = 14;
const IMAGE_ADJUSTED_DATA = 15;
const IMAGE_ENHANCED_DATA = 17;
const IMAGE_THUMBNAIL_DATA = 12;
/** TSD.ImageAdjustmentsArchive field numbers. */
export const ImageAdjustments = protoFields("TSD.ImageAdjustmentsArchive", {
    EXPOSURE: "exposure",
    SATURATION: "saturation",
    CONTRAST: "contrast",
    HIGHLIGHTS: "highlights",
    SHADOWS: "shadows",
    SHARPNESS: "sharpness",
    DENOISE: "denoise",
    TEMPERATURE: "temperature",
    TINT: "tint",
    BOTTOM_LEVEL: "bottom_level",
    TOP_LEVEL: "top_level",
    GAMMA: "gamma",
    ENHANCE: "enhance",
    REPRESENTS_SAGE_ADJUSTMENTS: "represents_sage_adjustments",
});
const FILTER_FIELDS = [
    ["exposure", ImageAdjustments.EXPOSURE, "float"],
    ["saturation", ImageAdjustments.SATURATION, "float"],
    ["contrast", ImageAdjustments.CONTRAST, "float"],
    ["highlights", ImageAdjustments.HIGHLIGHTS, "float"],
    ["shadows", ImageAdjustments.SHADOWS, "float"],
    ["sharpness", ImageAdjustments.SHARPNESS, "float"],
    ["denoise", ImageAdjustments.DENOISE, "float"],
    ["temperature", ImageAdjustments.TEMPERATURE, "float"],
    ["tint", ImageAdjustments.TINT, "float"],
    ["bottomLevel", ImageAdjustments.BOTTOM_LEVEL, "float"],
    ["topLevel", ImageAdjustments.TOP_LEVEL, "float"],
    ["gamma", ImageAdjustments.GAMMA, "float"],
    ["enhance", ImageAdjustments.ENHANCE, "bool"],
];
export class ImageModel extends DrawableModel {
    constructor(store, object) {
        if (object.type !== TSD_TYPE.IMAGE) {
            throw new RangeError(`object ${object.identifier} is not a TSD.ImageArchive`);
        }
        super(store, object);
    }
    /** Data-space identifier of the primary backing media, if any. */
    get dataId() {
        return this.object.message.getMessage(Image.DATA)?.getVarint(1);
    }
    /**
     * Every media variant this image references, in preference order:
     * the primary image, then the original, adjusted, enhanced and thumbnail
     * variants the apps keep alongside it.
     */
    dataVariants() {
        const roles = [
            ["data", Image.DATA],
            ["originalData", Image.ORIGINAL_DATA],
            ["adjustedImageData", IMAGE_ADJUSTED_DATA],
            ["enhancedImageData", IMAGE_ENHANCED_DATA],
            ["thumbnailData", IMAGE_THUMBNAIL_DATA],
        ];
        const out = [];
        for (const [role, field] of roles) {
            const id = this.object.message.getMessage(field)?.getVarint(1);
            if (id !== undefined)
                out.push({ role, dataId: id, fileName: this.store.dataFileName(id) });
        }
        return out;
    }
    /**
     * File name of the primary backing media within `Data/`.
     *
     * Note this is `TSP.DataInfo.file_name` when set (the real on-disk name,
     * which the apps disambiguate by appending the data identifier), falling
     * back to `preferred_file_name`.
     */
    get fileName() {
        const id = this.dataId;
        return id === undefined ? undefined : this.store.dataFileName(id);
    }
    /**
     * True when the primary media is actually present in the package. Apple
     * documents can reference media that was never materialized (optimized
     * storage, template assets); those images render in the app but have no
     * bytes to extract here.
     */
    get isMaterialized() {
        return this.bytesFor(this.fileName) !== undefined;
    }
    bytesFor(name) {
        if (name === undefined)
            return undefined;
        return (this.store.pendingFiles.get(`Data/${name}`) ??
            this.store.container.otherFiles().get(`Data/${name}`));
    }
    /**
     * Raw bytes of the backing media. Falls back to any other materialized
     * variant (original/adjusted/enhanced/thumbnail) when the primary is not
     * present in the package; `dataSource()` reports which one was used.
     */
    data() {
        for (const variant of this.dataVariants()) {
            const bytes = this.bytesFor(variant.fileName);
            if (bytes !== undefined)
                return bytes;
        }
        return undefined;
    }
    /** Which media variant {@link data} would return, if any. */
    dataSource() {
        for (const variant of this.dataVariants()) {
            if (this.bytesFor(variant.fileName) !== undefined)
                return variant;
        }
        return undefined;
    }
    /** Intrinsic pixel size recorded by the app, if present. */
    get originalSize() {
        const size = this.object.message.getMessage(Image.ORIGINAL_SIZE);
        const width = size?.getFloat(SizeFields.WIDTH);
        const height = size?.getFloat(SizeFields.HEIGHT);
        return width !== undefined && height !== undefined ? { width, height } : undefined;
    }
    /** True when the image is clipped by a mask (shape crop / instant alpha). */
    get hasMask() {
        return this.object.message.has(Image.MASK);
    }
    /** The mask drawable defining the crop, if the image has one. */
    mask() {
        const target = this.store.resolve(refId(this.object.message, Image.MASK));
        return target ? new MaskModel(this.store, target) : undefined;
    }
    /**
     * The crop, in both the spaces that matter.
     *
     * `window` is the visible rectangle in the image's own coordinates —
     * which part of the picture shows. `visible` is where that lands in the
     * image's parent, which is `image.position + mask.position` (see
     * `docs/FORMAT.md` §8.2). An uncropped image has no crop at all.
     */
    crop() {
        const mask = this.mask();
        const image = this.geometry();
        const window = mask?.geometry();
        if (!mask || !image || !window)
            return undefined;
        const full = {
            x: image.x ?? 0,
            y: image.y ?? 0,
            width: image.width ?? 0,
            height: image.height ?? 0,
        };
        const rect = {
            x: window.x ?? 0,
            y: window.y ?? 0,
            width: window.width ?? 0,
            height: window.height ?? 0,
        };
        return {
            window: rect,
            visible: { x: full.x + rect.x, y: full.y + rect.y, width: rect.width, height: rect.height },
            full,
            isRectangular: mask.isRectangular,
        };
    }
    /**
     * Choose which part of the picture shows, in image-local points —
     * the image's *drawn* geometry space, not source pixels: an image
     * scaled to 260 pt wide crops with windows inside 260, wherever the
     * source's pixel count landed. A window outside the drawn frame is
     * one the app renders as a broken top-left crop and refuses to open
     * the mask editor on.
     *
     * The visible rectangle moves with the window: cropping to `{x: 10, …}`
     * shifts what appears on the page 10pt right, because the window is
     * positioned relative to the image. To keep the result where it was, call
     * {@link setVisibleFrame} afterwards — or use it instead, which does both.
     *
     * An image with no mask gets one, built as the rectangle Apple writes.
     */
    setCrop(window) {
        const existing = this.mask();
        if (existing) {
            existing.setGeometry({ x: window.x, y: window.y });
            existing.setSize(window.width, window.height);
            return;
        }
        const component = this.store.componentOf(this.object.identifier);
        if (!component) {
            throw new RangeError(`image ${this.id} is not in a component; cannot add a mask`);
        }
        const mask = buildRectangularMask(this.store, window, component, {
            parentId: this.object.identifier,
        });
        this.object.message.setMessage(Image.MASK, makeRef(mask.identifier));
        // A masked image states its resize behavior: all 87 masked corpus
        // images carry aspect_ratio_locked true, and locked is stated on each
        // (false on 85). An already-locked image keeps its lock.
        const drawable = this.object.message.getMessage(Image.SUPER);
        if (drawable) {
            if (drawable.getUint(Drawable.LOCKED) === undefined) {
                drawable.setBool(Drawable.LOCKED, false);
            }
            drawable.setBool(Drawable.ASPECT_RATIO_LOCKED, true);
            this.object.message.markDirty();
        }
        this.object.setObjectReferences([
            ...new Set([...this.object.getObjectReferences(), mask.identifier]),
        ]);
    }
    /**
     * Place the cropped result at a rectangle in the parent's space.
     *
     * Keeps the same part of the picture visible: the image slides so that
     * `image.position + mask.position` lands on `frame`, and the window is
     * resized in place. This is the operation "move and resize the cropped
     * image", as opposed to {@link setCrop}'s "choose what shows".
     */
    setVisibleFrame(frame) {
        const crop = this.crop();
        if (!crop) {
            this.setGeometry(frame);
            return;
        }
        this.setGeometry({ x: frame.x - crop.window.x, y: frame.y - crop.window.y });
        this.mask().setSize(frame.width, frame.height);
    }
    /**
     * Show the whole picture again.
     *
     * The mask object is left in the package — something else may reference
     * it, and this library never collects the graph — but the image no longer
     * points at it, so the full extent shows at the image's own frame. That
     * frame is larger than the crop was, which is the point.
     */
    removeCrop() {
        if (!this.hasMask)
            return false;
        const maskId = refId(this.object.message, Image.MASK);
        this.object.message.remove(Image.MASK);
        this.object.setObjectReferences(this.object.getObjectReferences().filter((id) => id !== maskId));
        return true;
    }
    /** True when any image filter is applied. */
    get hasFilters() {
        return this.object.message.has(IMAGE_ADJUSTMENTS);
    }
    /** Current image-filter settings ({} when none are applied). */
    filters() {
        const adjustments = this.object.message.getMessage(IMAGE_ADJUSTMENTS);
        const out = {};
        if (!adjustments)
            return out;
        for (const [key, field, kind] of FILTER_FIELDS) {
            const value = kind === "float" ? adjustments.getFloat(field) : adjustments.getBool(field);
            if (value !== undefined) {
                out[key] = value;
            }
        }
        return out;
    }
    /**
     * Apply image filters. Only the properties given are changed; pass
     * `undefined` for a property to clear it. The apps re-render from the
     * untouched original media, so this is non-destructive.
     */
    setFilters(filters) {
        let adjustments = this.object.message.getMessage(IMAGE_ADJUSTMENTS);
        if (!adjustments) {
            adjustments = RawMessage.create();
            this.object.message.setMessage(IMAGE_ADJUSTMENTS, adjustments);
        }
        for (const [key, field, kind] of FILTER_FIELDS) {
            if (!(key in filters))
                continue;
            const value = filters[key];
            if (value === undefined) {
                adjustments.remove(field);
            }
            else if (kind === "float") {
                adjustments.setFloat(field, value);
            }
            else {
                adjustments.setBool(field, value);
            }
        }
    }
    /** Remove all image filters, restoring the unadjusted rendering. */
    clearFilters() {
        this.object.message.remove(IMAGE_ADJUSTMENTS);
    }
}
/** All images in a document. */
export function imagesOf(store) {
    const out = [];
    for (const { obj } of store.allObjects()) {
        if (obj.type === TSD_TYPE.IMAGE)
            out.push(new ImageModel(store, obj));
    }
    return out;
}
//# sourceMappingURL=images.js.map