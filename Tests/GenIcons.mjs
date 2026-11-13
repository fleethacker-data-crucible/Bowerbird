// Comment removal in tools/gen-icons.mjs. Node is CI-only, never required on the workstation.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { shapesFromSvg, stripHtmlComments } from '../tools/gen-icons.mjs';

assert.equal(stripHtmlComments('no comment'), 'no comment');
assert.equal(stripHtmlComments('<!-- @license lucide-static v1.54.0 - ISC -->'), '');
assert.equal(stripHtmlComments('a<!-- one -->b<!-- two -->c'), 'abc');
assert.equal(stripHtmlComments('<!-- <!-- --> -->'), ' -->');
assert.equal(stripHtmlComments('<!-- unclosed'), '');

// Deleting one <!--...--> match turns this back into <!--. The scan removes that too.
const reassembled = '<<!-- -->!--';
assert.equal(stripHtmlComments(reassembled), '');
assert.equal(reassembled.replace(/<!--[\s\S]*?-->/g, ''), '<!--');

const license = '<!-- @license lucide-static v1.54.0 - ISC -->\n<svg>\n  <path d="M5 12h14" />\n</svg>\n';
assert.deepEqual(shapesFromSvg(license), [['path', { d: 'M5 12h14' }]]);

const hidden = '<svg>\n<!-- <path d="EVIL" /> -->\n<path d="M1 1" />\n<circle cx="12" cy="12" r="2" />\n</svg>\n';
assert.deepEqual(shapesFromSvg(hidden), [
  ['path', { d: 'M1 1' }],
  ['circle', { cx: '12', cy: '12', r: '2' }],
]);

// The reassembled marker opens a comment that runs to end of file, so the path is comment text.
const hostile = '<svg>\n<<!-- -->!--\n<path d="M9 9" />\n</svg>\n';
assert.equal(stripHtmlComments(hostile).includes('<!--'), false);
assert.deepEqual(shapesFromSvg(hostile), []);

// A second closer finishes the reassembled comment and leaves the real shape.
const closedAgain = '<svg>\n<<!-- -->!-- -->\n<path d="M1 1" />\n</svg>\n';
assert.deepEqual(shapesFromSvg(closedAgain), [['path', { d: 'M1 1' }]]);

const script = fileURLToPath(new URL('../tools/gen-icons.mjs', import.meta.url));
const cli = spawnSync(process.execPath, [script], { encoding: 'utf8' });
assert.equal(cli.status, 1);
assert.match(cli.stderr, /usage: node tools\/gen-icons\.mjs/);

console.log('PASS: icon comment scan');
