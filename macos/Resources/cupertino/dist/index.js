/**
 * cupertino-files — read, inspect and edit Apple iWork documents (Pages, Numbers,
 * Keynote) in pure TypeScript with zero runtime dependencies.
 *
 * Layering (each importable on its own):
 *   primitives:  snappy, protobuf wire (RawMessage), zip, varint, crc32
 *   container:   IWorkContainer (package layouts), IWA archives (IwaObject)
 *   graph:       ObjectStore (components, IDs, references, save invariants)
 *   model:       IWorkDocument + TextStorage/StylesheetModel/DrawableModel
 *   apps:        PagesDocument, NumbersDocument, KeynoteDocument
 */
// High-level documents
export { PagesDocument, PagesSection } from "./pages/document.js";
export { NumbersDocument } from "./numbers/document.js";
export { KeynoteDocument, KeynoteSlide } from "./keynote/document.js";
export { PlaceholderKind, ShowMode } from "./keynote/document.js";
export * as keynoteSchema from "./keynote/schema.js";
export { IWorkDocument, FormatInfo, detectApp } from "./tsa/document.js";
// Shared model
export { TextStorage, OBJECT_REPLACEMENT_CHARACTER, FOOTNOTE_MARK_CHARACTER, STORAGE_KIND, } from "./tswp/textstorage.js";
export { buildNumberAttachment, readNumberAttachment, ATTACHMENT_TYPE, AttachmentKind, NumberAttachment, TextualAttachment, PAGE_NUMBER_FORMATS, buildDateField, buildBookmark, readDateField, SMART_FIELD_TYPE, SmartField, DateTimeField, DateTimeStyle, DateTimeUpdatePlan, BookmarkFieldArchive, } from "./tswp/fields.js";
export { buildComment, createAuthor, resolveAuthor, authorsOf, readCommentStorage, COMMENT_TYPE, HighlightFields, CommentStorageFields, AuthorFields, } from "./tswp/comments.js";
export { randomUuid, isUuidString } from "./base/uuid.js";
export { StylesheetModel, StyleHandle, describeStyle, buildCharacterProperties, buildParagraphProperties, applyCharacterProperties, applyParagraphProperties, readCharacterProperties, readParagraphProperties, } from "./tss/stylesheet.js";
// Shared style values (fills, gradients, strokes, shadows, padding)
export { readColor, writeColor, isColorLike, hexColor, BLACK, WHITE, readFill, writeFill, colorFill, linearGradient, readStroke, writeStroke, solidStroke, readShadow, writeShadow, readPadding, writePadding, FillFields, GradientFields, GradientType, ImageFillFields, ImageFillTechnique, StrokeFields, StrokePatternFields, StrokePatternType, LineCap, LineJoin, ShadowFields, ShadowType, DEFAULT_SHADOW, PaddingFields, } from "./tsd/style.js";
export { DrawableModel, DrawableStyleHandle, findDrawableCore, drawableStylesOf, } from "./tsd/drawables.js";
export { ImageModel, imagesOf, ImageAdjustments } from "./tsd/images.js";
export { MaskModel, buildRectangularMask, MaskFields, PathSourceFields, BezierPathSourceFields, PathElementType, } from "./tsd/masks.js";
export { DrawableContainer, drawableById } from "./tsd/placement.js";
export { ChartModel, chartsOf, decodeGridValue, encodeGridValue, CHART_TYPE_NAMES, CHART_TYPE_IDS, TSCH_TYPE, } from "./tsch/charts.js";
export { ChartStyleArchive, ChartSeriesStyle, ChartAxisStyle, ChartLegendStyle, SeriesStyleProperty, AxisStyleProperty, LegendStyleProperty, GENERATED_PROPERTIES, sparseRefs, sparseCount, } from "./tsch/appearance.js";
export * as tspSchema from "./tsp/schema.js";
export * as tswpSchema from "./tswp/schema.js";
export * as tssSchema from "./tss/schema.js";
export * as tsdSchema from "./tsd/schema.js";
export { TableModel, tablesOf, decodeCellRecord, cellValueToString, groupValueOf, normalizeCellInput, TST_TYPE, TableModelFields, } from "./tst/tables.js";
export { CellRecord, CellType, CellFlag, encodeDecimal128, decodeDecimal128 } from "./tst/cellrecord.js";
export { renderFormula, registerFormulaFunctions, clearRegisteredFormulaFunctions, functionName, isKnownFunction, functionTableProvenance, columnName, cellAddress, AstNodeType, AstNodeFields, FormulaFields, CROSS_TABLE_PREFIX, SELF_CELL_MARKER, } from "./tst/formulas.js";
export { TableStyleHandle, readCellFormatting, applyCellFormatting, buildCellProperties, readTableFormatting, applyTableFormatting, allBorders, CellStyleProps, TableStyleProps, VerticalAlignment, TST_STYLE_TYPE, } from "./tst/styles.js";
export { readFormat, writeFormat, categoryOfFormatType, flagForFormat, FormatType, FormatFields, NegativeStyle, AUTOMATIC_DECIMALS, FORMAT_FLAG_BY_CATEGORY, } from "./tst/formats.js";
export { readPredicate, readOperand, describePredicate, PredicateFields, PrePivotPredicateFields, PredArgFields, PredArgDataFields, PREDICATE_TYPE_OPERATORS, PREDICATE_TYPE_FUNCTIONS, } from "./tst/predicates.js";
export { ConditionalStyleSet, ConditionalStyleSetFields } from "./tst/conditional.js";
export { FilterSet, FilterSetFields, FilterSetType } from "./tst/filters.js";
export { TableCategories, categoriesOf, expandIndexSet, writeIndexSet, readCellValue, GroupingType, GROUPING_TYPE_NAMES, GroupByFields, GroupColumnFields, GroupNodeFields, ColumnAggregateFields, sameGroupValue, } from "./tst/categories.js";
export { ColumnRowUidMap, uidMapOf, readUid, uidKey, UidMapFields } from "./tst/uidmap.js";
export { FormulaOwnerRegistry, ownerKey, readOwnerUid, readCfUid, OwnerKind, OWNER_KIND_NAMES, DOCUMENT_OWNER_UID, FormulaOwnerFields, FORMULA_OWNER_DEPENDENCIES, HAUNTED_OWNER, } from "./tsce/owners.js";
export { controlsOf, readControlList, readCellSpec, controlShape, CellSpecFields, CONTROL_CELL_SPEC_TABLE, InteractionType, INTERACTION_TYPE_NAMES, } from "./tst/controls.js";
export { buildFormula, parseFormula, parseReference, authorableFunctions, } from "./tst/formula-builder.js";
export { decodePreBncRecord, splitPreBncRow, PRE_BNC_VERSION, PRE_BNC_LAYOUTS } from "./tst/prebnc.js";
export { BuildModel, buildsOfSlide, removeBuild, BUILD_TYPE, BuildFields, BuildChunkFields, BuildAttributesFields, TextDelivery, DeliveryOption, Acceleration, } from "./keynote/builds.js";
export { TextRange, ParagraphHandle } from "./tswp/range.js";
export { TableOfContents, tablesOfContents, TOC_TYPE, TocScope } from "./tswp/toc.js";
export { BorderPosition, Capitalization, Ligatures, ScriptPosition, StrikethruType, TabAlignment, TextAlignment, UnderlineType, } from "./tswp/schema.js";
export { PagesSettings } from "./pages/document.js";
export { sha1 } from "./base/sha1.js";
export { IWorkVersion, eraOf, eraInfo, eraAtLeast, probeStructure, buildCompatibilityReport, summarizeCompatibility, IWORK_ERAS, HIGHEST_KNOWN_FORMAT_MAJOR, } from "./tsp/version.js";
export { imageDimensions } from "./base/imagesize.js";
export * as pagesSchema from "./pages/schema.js";
// Object graph & container
export { ObjectStore, Component } from "./tsp/store.js";
export { deepCloneObject, defaultFollow } from "./tsp/clone.js";
export { IWorkContainer, EncryptedDocumentError, canonicalIwaName, locatorForIwaName } from "./tsp/package.js";
export { IwaObject, parseIwaFile, serializeIwaFile, parseIwaStream, serializeIwaStream } from "./tsp/iwa.js";
// Registry
export { typeName, registerTypes, clearRegisteredTypes, SHARED_TYPES, PAGES_TYPES, KEYNOTE_TYPES, NUMBERS_TYPES, } from "./tsp/registry.js";
// Primitives
export { RawMessage, WireType } from "./base/protobuf.js";
export { snappyCompressBlock, snappyUncompressBlock, decodeIwaData, encodeIwaData, detectIwaFraming, UnsupportedIwaFramingError, } from "./base/snappy.js";
export { decodeLzfseStream, decodeLzfseBlocks, decodeLzvn } from "./base/lzfse.js";
export { ZipReader, buildZip } from "./base/zip.js";
export { inflateRaw } from "./base/inflate.js";
export { crc32 } from "./base/crc32.js";
export { readUvarint, writeUvarint, uvarintLength, zigzagDecode, zigzagEncode } from "./base/varint.js";
export { ByteWriter, concatBytes, bytesEqual, utf8Decode, utf8Encode } from "./base/bytes.js";
export { parseBinaryPlist, xmlPlistStrings } from "./base/plist.js";
//# sourceMappingURL=index.js.map