// Social crawlers generally do not run React. Serve route-specific metadata in
// real HTML; the same compiled app handles the page once the browser loads it.
import {readFile,writeFile} from 'node:fs/promises';
const index=new URL('../dist/index.html',import.meta.url);
const home=await readFile(index,'utf8');
const title='EXP for teams — how does your team actually work?';
const description='the component library. the code. the bits that don’t agree. help me figure out what EXP for teams needs to do.';
let teams=home.replace(/<title>[^<]*<\/title>/,`<title>${title}</title>`);
for(const [attribute,key,value] of [
  ['property','og:title',title],['name','twitter:title',title],
  ['property','og:description',description],['name','twitter:description',description],['name','description',description],
  ['property','og:url','https://expdesign.app/teams'],
]) teams=teams.replace(new RegExp(`<meta\\s+${attribute}="${key}"\\s+content="[^"]*"\\s*\\/?>(?:\\s*)`),`<meta ${attribute}="${key}" content="${value}">\n`);
teams=teams.replace(/<link rel="canonical" href="[^"]*"\s*\/?>/,'<link rel="canonical" href="https://expdesign.app/teams">');
await writeFile(new URL('../dist/teams.html',import.meta.url),teams);
console.log('Built crawler-readable /teams metadata.');
