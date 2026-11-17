import {readFileSync,writeFileSync,copyFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const icon=resolve(root,'assets/icon/CloakTools.icon');
const definition=JSON.parse(readFileSync(resolve(icon,'icon.json'),'utf8'));
const paths=[...definition.groups[0].layers].reverse().map(layer=>{
  const svg=readFileSync(resolve(icon,'Assets',layer['image-name']),'utf8');
  return svg.match(/<svg[^>]*>([\s\S]*)<\/svg>/)[1].replace(/<title>[\s\S]*?<\/title>/,'');
}).join('');
const color='#'+definition.fill.solid.split(':')[1].split(',').slice(0,3).map(x=>Math.round(Number(x)*255).toString(16).padStart(2,'0')).join('');
const mark=`<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" role="img" aria-labelledby="cloaktools-mark-title" data-logo-spec="cloakyard-mark-v1"><title id="cloaktools-mark-title">CloakTools</title><defs><clipPath id="cloaktools-circle"><circle cx="32" cy="32" r="30"/></clipPath></defs><circle cx="32" cy="32" r="30" fill="${color}"/><g clip-path="url(#cloaktools-circle)"><g transform="translate(2 2) scale(.05859375)">${paths}</g></g><circle cx="32" cy="32" r="29.25" fill="none" stroke="#3067CD" stroke-opacity=".14" stroke-width="1.5"/></svg>\n`;
for(const path of ['assets/logo/cloaktools-mark.svg','apps/site/public/cloaktools-mark.svg']) writeFileSync(resolve(root,path),mark);
copyFileSync(resolve(root,'assets/icon/Previews/Default-512.png'),resolve(root,'apps/site/public/cloaktools.png'));
console.log('Synced circular web mark from the native icon layers.');

for (const appearance of ['light', 'dark']) copyFileSync(resolve(root, `assets/screenshots/new-files-${appearance}.png`), resolve(root, `apps/site/public/images/new-files-${appearance}.png`));
// The social card is checked in; regeneration is an explicit design task.
if (existsSync(resolve(root, 'assets/social/og.png'))) copyFileSync(resolve(root, 'assets/social/og.png'), resolve(root, 'apps/site/public/og.png'));
