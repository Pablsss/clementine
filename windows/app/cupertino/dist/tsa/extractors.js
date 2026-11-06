import { TSWP_REFERENCE_EXTRACTORS } from "../tswp/schema.js";
import { TSS_REFERENCE_EXTRACTORS } from "../tss/schema.js";
import { TSD_REFERENCE_EXTRACTORS } from "../tsd/schema.js";
export const SHARED_REFERENCE_EXTRACTORS = new Map([
    ...TSWP_REFERENCE_EXTRACTORS,
    ...TSS_REFERENCE_EXTRACTORS,
    ...TSD_REFERENCE_EXTRACTORS,
]);
//# sourceMappingURL=extractors.js.map