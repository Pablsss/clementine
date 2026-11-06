import { PagesDocument } from './cupertino/dist/pages/document.js';
import { readFileSync, writeFileSync } from 'node:fs';
import { basename,dirname,join } from 'node:path';
const [mode, source, destination, ...assets] = process.argv.slice(2);
if (mode === 'write') {
    const doc = PagesDocument.blank();
    doc.body.setText(readFileSync(source,'utf8'));
    for (const asset of assets) {
        doc.insertInlineImage(doc.body.text.length,readFileSync(asset),{fileName:basename(asset),maxWidth:440});
    }
    writeFileSync(destination,doc.save());
} else {
    const doc = PagesDocument.load(readFileSync(source));
    const text = [doc.bodyOrUndefined?.text,...doc.textBoxes().map(box=>box.storage.text),
        ...doc.tables().map(t=>t.grid().map(row=>row.join('\t')).join('\n'))].filter(Boolean).join('\n').replaceAll('\uFFFC','');
    const images=[];
    for(const image of doc.images()){
        const data=image.data();if(!data)continue;
        const filename=join(dirname(destination),'graphic-'+images.length+'-'+basename(image.fileName || 'image.png'));
        writeFileSync(filename,data);images.push(filename);
    }
    writeFileSync(destination,JSON.stringify({text,images}));
}
