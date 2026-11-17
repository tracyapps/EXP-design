import assert from 'node:assert/strict';
import {readFile,stat} from 'node:fs/promises';
import sharp from 'sharp';
import {fileURLToPath} from 'node:url';
const root=new URL('../dist/',import.meta.url);
for(const [file,url] of [['index.html','https://expdesign.app/'],['teams.html','https://expdesign.app/teams'],['share.html','https://expdesign.app/share']]){
 const html=await readFile(new URL(file,root),'utf8');
 const tags=[...html.matchAll(/<meta\s+(?:property|name)="([^"]+)"\s+content="([^"]*)"\s*\/?>/g)];
 const values=new Map(tags.map(match=>[match[1],match[2]]));
 for(const key of ['og:type','og:title','og:description','og:url','og:image','og:image:alt','twitter:card','twitter:image']){
  assert.equal(tags.filter(match=>match[1]===key).length,1,`${file}: exactly one ${key}`);assert.ok(values.get(key),`${file}: nonempty ${key}`);
 }
 assert.equal(values.get('og:url'),url);assert.ok(html.includes(`<link rel="canonical" href="${url}">`));
 assert.equal(values.get('twitter:card'),'summary_large_image');assert.equal(values.get('twitter:image'),values.get('og:image'));
 const imageURL=new URL(values.get('og:image'));assert.equal(imageURL.origin,'https://expdesign.app');
 const image=new URL(`.${imageURL.pathname}`,root);const meta=await sharp(fileURLToPath(image)).metadata();
 assert.equal(meta.format,'png');assert.equal(meta.width,1200);assert.equal(meta.height,630);
 assert.equal(values.get('og:image:width'),'1200');assert.equal(values.get('og:image:height'),'630');
 assert.ok((await stat(image)).size<5*1024*1024);console.log(`${file}: metadata, canonical, real 1200×630 PNG, and large-image card pass`);
}
