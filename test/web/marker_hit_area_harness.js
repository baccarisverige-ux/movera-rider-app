// Applies the <style> rules of a page (argv[2], e.g. web/index.html) to a
// small model of Google's map DOM and prints the resulting `visibility` of
// each image as JSON. Supports the selector subset the page uses for map
// images: descendant combinators, .class, tag and [attr*="value"].
'use strict';
const fs = require('fs');

const html = fs.readFileSync(process.argv[2], 'utf8');
const css = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)]
  .map((m) => m[1].replace(/\/\*[\s\S]*?\*\//g, ''))
  .join('\n');

const rules = [];
for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
  const decls = {};
  for (const d of m[2].split(';')) {
    const i = d.indexOf(':');
    if (i > 0) decls[d.slice(0, i).trim()] = d.slice(i + 1).trim();
  }
  for (const sel of m[1].split(',')) rules.push({ sel: sel.trim(), decls });
}

function node(tag, attrs, parent) {
  return { tag, attrs, parent, cls: (attrs.class || '').split(/\s+/) };
}

function compound(part, el) {
  const m = part.match(/^([a-z]*)((?:\.[\w-]+)*)((?:\[[^\]]+\])*)$/i);
  if (!m) return false;
  if (m[1] && m[1].toLowerCase() !== el.tag) return false;
  for (const c of m[2].split('.').filter(Boolean)) {
    if (!el.cls.includes(c)) return false;
  }
  for (const a of m[3].matchAll(/\[([\w-]+)\*="([^"]*)"\]/g)) {
    if (!(el.attrs[a[1]] || '').includes(a[2])) return false;
  }
  return m[0].length > 0;
}

function matches(sel, el) {
  const parts = sel.split(/\s+/);
  if (!compound(parts.pop(), el)) return false;
  let cur = el.parent;
  while (parts.length && cur) {
    if (compound(parts[parts.length - 1], cur)) parts.pop();
    cur = cur.parent;
  }
  return parts.length === 0;
}

function visibility(el) {
  let v = 'visible';
  for (const r of rules) {
    if (r.decls.visibility && matches(r.sel, el)) {
      v = r.decls.visibility.replace(/\s*!important$/, '');
    }
  }
  return v;
}

const body = node('body', {}, null);
const map = node('div', { class: 'gm-style' }, body);
const layer = node('div', {}, map);
const hitArea = node('img', {
  src: 'https://maps.gstatic.com/mapfiles/transparent.png',
}, layer);
const tile = node('img', {
  src: 'https://maps.googleapis.com/maps/vt?pb=!1m5',
}, layer);
const outside = node('img', { src: '/mapfiles/transparent.png' }, body);

process.stdout.write(JSON.stringify({
  rules: rules.length,
  hitArea: visibility(hitArea),
  tile: visibility(tile),
  outside: visibility(outside),
}));
