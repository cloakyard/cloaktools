import {readFileSync, existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root = resolve(import.meta.dirname, '../../..');
const bundle = JSON.parse(readFileSync(resolve(root, 'docs/air/bundle.json'), 'utf8'));
for (const [file, hash] of Object.entries(bundle.files)) {
  assert.equal(createHash('sha256').update(readFileSync(resolve(root, file))).digest('hex'), hash, `Air drift: ${file}`);
}
assert.ok(readFileSync(resolve(root, 'apps/site/DESIGN.md'), 'utf8').startsWith(readFileSync(resolve(root, 'docs/air/contract.md'), 'utf8')), 'Standalone website design must contain the complete pinned contract');
assert.doesNotMatch(readFileSync(resolve(root, 'apps/site/src/styles/global.css'), 'utf8'), /--air-[\w-]+\s*:/, 'Product CSS must not override shared Air tokens');
const dist = resolve(import.meta.dirname, '../dist');
const pages = ['index.html', 'install/index.html', 'privacy/index.html', 'support/index.html', 'source/index.html', 'license/index.html', '404.html'];
const readingPages = ['install/index.html', 'privacy/index.html', 'support/index.html', 'source/index.html'];
const read = file => readFileSync(resolve(dist, file), 'utf8');
const ids = html => [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]);
const footer = read('index.html').match(/<footer\b[\s\S]*?<\/footer>/)[0];
let linkCount = 0;
for (const page of pages) {
  const html = read(page);
  assert.match(html, /<html lang="en"/);
  assert.match(html, /<main\b[^>]*id="main"[^>]*tabindex="-1"|<main\b[^>]*tabindex="-1"[^>]*id="main"/);
  assert.match(html, /rel="canonical" href="https:\/\/tools.cloakyard.com/);
  assert.equal((html.match(/<h1[ >]/g) || []).length, 1, `one h1: ${page}`);
  assert.equal((html.match(/<main[ >]/g) || []).length, 1, `one main: ${page}`);
  assert.equal(ids(html).length, new Set(ids(html)).size, `duplicate IDs: ${page}`);
  assert.match(html, /aria-label="Primary navigation"/);
  assert.match(html, /aria-label="Footer navigation"/);
  assert.equal(html.match(/<footer\b[\s\S]*?<\/footer>/)[0].replace(/ aria-current="page"/g, ''), footer, `Shared footer: ${page}`);
  assert.match(html, /href="https:\/\/github.com\/cloakyard\/cloaktools"/);
  assert.match(html, /href="https:\/\/github.com\/cloakyard\/cloaktools\/blob\/main\/LICENSE"/);
  for (const [, href] of html.matchAll(/(?:href|src|srcset)="((?:\/|#)[^"]*)"/g)) {
    const url = new URL(href.replaceAll('&amp;', '&'), `https://tools.cloakyard.com/${page}`);
    let file = decodeURIComponent(url.pathname).slice(1);
    if (!file || file.endsWith('/')) file += 'index.html';
    assert.ok(existsSync(resolve(dist, file)), `${page}: missing ${href}`);
    if (url.hash && file.endsWith('.html')) assert.ok(ids(read(file)).includes(decodeURIComponent(url.hash.slice(1))), `${page}: missing anchor ${href}`);
    linkCount++;
  }
  for (const img of html.matchAll(/<img\b[^>]*>/g)) assert.match(img[0], /\balt="[^"]*"/, `Image alt: ${page}`);
  assert.ok(!html.includes('https://fonts.'), 'No remote fonts');
  assert.doesNotMatch(html, /maximum-scale=1|user-scalable=no/, 'Pinch zoom remains enabled');
  if (readingPages.includes(page)) {
    const article = html.match(/<article\b[\s\S]*?<\/article>/)[0];
    const headings = [...article.matchAll(/<h2\b[^>]*id="([^"]+)"/g)].map(m => m[1]);
    const contents = html.match(/<details class="air-contents"[\s\S]*?<\/details>/)?.[0];
    assert.ok(contents, `Native shared contents: ${page}`);
    assert.deepEqual([...contents.matchAll(/href="#([^"]+)"/g)].map(m => m[1]), headings, `Complete, ordered contents: ${page}`);
    assert.match(article, /<section\b[^>]*><h2 tabindex="-1"/, `Air reading sections: ${page}`);
  }
}
assert.match(read('404.html'), /name="robots" content="noindex"/);
assert.match(read('index.html'), /<picture><source media="\(prefers-color-scheme: dark\)"/);
assert.match(read('index.html'), /<button class="air-artwork-replay"[^>]*aria-label="Replay CloakTools animation"/);
console.log(`Verified ${pages.length} routes, ${linkCount} local links/assets/anchors, complete contents, shared shell, metadata and pinned Air hashes.`);
