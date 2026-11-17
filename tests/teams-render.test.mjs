import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from '../website/node_modules/esbuild/lib/main.js';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const result=await build({stdin:{contents:`import React from 'react'; import {renderToStaticMarkup} from 'react-dom/server'; import TeamsPage from './src/TeamsPage.jsx'; export function render(mode){return renderToStaticMarkup(<TeamsPage mode={mode}/>);}`,resolveDir:fileURLToPath(new URL('../website',import.meta.url)),loader:'jsx'},bundle:true,write:false,platform:'node',format:'cjs',loader:{'.css':'empty'}});
const compiled={exports:{}};new Function('require','module','exports',result.outputFiles[0].text)(createRequire(import.meta.url),compiled,compiled.exports);
globalThis.window={location:{origin:'https://example.test',hash:`#${'a'.repeat(43)}`,pathname:'/teams'}};
test('survey renders native labels, optional questions and no email demand',()=>{
 const html=compiled.exports.render('survey');assert.match(html,/how does your team actually work/);assert.match(html,/all questions are optional/);assert.ok(!html.includes('type="email"'));
 for(const id of ['team-role','team-size','team-problem','team-stack','team-approval','team-barrier']){assert.ok(html.includes(`for="${id}"`));assert.ok(html.includes(`id="${id}"`));}
 assert.match(html,/<fieldset[^>]*class="team-choices"><legend>what computers/);assert.match(html,/<details[^>]*><summary>/);assert.match(html,/role="status"/);
});
test('confirmation view requires a deliberate button; management offers withdrawal and deletion',()=>{
 const confirm=compiled.exports.render('confirm');assert.match(confirm,/<button[^>]*>yes, you can follow up<\/button>/);assert.ok(!confirm.includes('<form'));
 const manage=compiled.exports.render('manage');assert.match(manage,/>stop follow-up<\/button>/);assert.match(manage,/>delete my response<\/button>/);
});
