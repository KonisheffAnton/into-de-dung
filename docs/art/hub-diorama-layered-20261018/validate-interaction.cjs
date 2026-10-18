// Data and event-handler checks only. This is not a browser rendering test.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = __dirname;
const report = path.resolve(root, '../../../test_reports/hub-diorama-layered-20261018');
const context = {window: {}};
vm.runInNewContext(fs.readFileSync(path.join(root, 'scene-data.js'), 'utf8'), context);
const data = context.window.DIORAMA_LAYER_DATA;
const interaction = require('./interaction.js');
const masks = Object.fromEntries(data.clips.map(c => [c.id, c.masks.map(m => Buffer.from(m, 'base64'))]));
const fixtures = JSON.parse(fs.readFileSync(path.join(report, 'hit-fixtures.json'), 'utf8'));
for (const f of fixtures) {
  const frames = Object.fromEntries(data.clips.map(c => [c.id, f.frame]));
  const hit = interaction.hitTest(data.actors, f.x, f.y, masks, frames, data.foregroundZ, data.occlusionPolygons);
  assert.equal(hit?.id ?? null, f.expected, JSON.stringify(f));
}

function harness() {
  const nodes = [], images = [], raf = [];
  const matches = (node, selector) => selector.startsWith('.')
    ? node.className.split(' ').includes(selector.slice(1))
    : selector.startsWith('[') && node.attributes.has(selector.slice(1, -1));
  class Element {
    constructor(tag = 'div', attrs = []) {
      this.tag = tag; this.attributes = new Map(attrs.map(a => [a, '']));
      this.children = []; this.events = {}; this.dataset = {}; this.style = {};
      this.className = ''; this.hidden = false; this.draws = []; this.open = false;
      const highlights = new Set();
      this.classList = {toggle: (key, on) => on ? highlights.add(key) : highlights.delete(key), contains: key => highlights.has(key)};
      nodes.push(this);
      if (tag === 'img') {images.push(this); this.complete = false; this.naturalWidth = 0;}
    }
    addEventListener(type, handler) {(this.events[type] ||= []).push(handler);}
    async emit(type, event = {}) {for (const f of this.events[type] || []) await f({target:this, currentTarget:this, preventDefault(){}, ...event});}
    setAttribute(key, value) {this.attributes.set(key, value);}
    append(...items) {this.children.push(...items);}
    insertBefore(item) {this.children.push(item);}
    querySelector(selector) {
      const descend = n => n.children.flatMap(c => [c, ...descend(c)]);
      return descend(this).find(n => matches(n, selector));
    }
    getBoundingClientRect() {return {left:100, top:50, width:836, height:470.5};}
    getContext() {return {clearRect(){}, save(){}, restore(){}, translate(){}, scale(){}, drawImage:(image) => this.draws.push(image.src)};}
    showModal(){this.open = true;}
    close(){this.open = false;}
    async requestFullscreen(){document.fullscreenElement = this;}
  }
  const document = new Element('document');
  document.createElement = tag => new Element(tag);
  document.querySelectorAll = selector => nodes.filter(n => matches(n, selector));
  document.querySelector = selector => document.querySelectorAll(selector)[0];
  document.exitFullscreen = async () => {document.fullscreenElement = null;};
  for (const attr of ['data-global-status','data-frame-label','data-inspector','data-dialog-title','data-dialog-gif','data-dialog-link','data-selected','data-mode','data-pause','data-close']) new Element('div', [attr]);
  for (const direction of [-1, 1]) {const n = new Element('button',['data-step']); n.dataset.step = direction;}
  const scenes = data.backgrounds.map(bg => {
    const section = new Element(); section.className = 'scene'; section.dataset.scene = bg.id;
    const shell = new Element(); shell.className = 'stage-shell';
    const stage = new Element(); stage.className = 'stage';
    const background = new Element('img'); background.className = 'background';
    const status = new Element(); status.className = 'stage-status';
    const links = new Element(); links.className = 'scene-links';
    const fullscreen = new Element('button',['data-fullscreen']);
    stage.append(background, status); shell.append(stage); section.append(shell, links, fullscreen);
    return {section, shell, stage, status, fullscreen};
  });
  const env = {window:{DIORAMA_LAYER_DATA:data, DioramaInteraction:interaction}, document,
    Image:class extends Element{constructor(){super('img');}}, Uint8Array, Map, Set,
    atob:s => Buffer.from(s,'base64').toString('binary'), requestAnimationFrame:f => raf.push(f)};
  vm.runInNewContext(fs.readFileSync(path.join(root,'gallery.js'),'utf8'), env);
  return {document, nodes, images, scenes, frame:time => raf.shift()(time)};
}

(async () => {
  const h = harness(), d = h.document;
  const q = selector => d.querySelector(selector);
  const canvases = d.querySelectorAll('.actor-canvas');
  assert.equal(canvases.length,16);
  const mode = q('[data-mode]'), pause = q('[data-pause]');
  mode.value = 'hover'; await mode.emit('change'); await pause.emit('click');
  await d.querySelectorAll('[data-step]')[1].emit('click');
  assert.match(q('[data-frame-label]').textContent,/2 \/ 9/);
  assert(canvases.every(c => c.draws.length === 0));
  for (let i=0; i<h.images.length; i++) {
    const image = h.images[i]; image.complete = true; image.naturalWidth = 256; await image.emit('load');
    if (i < h.images.length-1) assert(h.scenes.every(s => !s.status.hidden));
  }
  assert(h.scenes.every(s => s.status.hidden));
  assert(canvases.every(c => c.draws.at(-1).endsWith('frame-02.png')),'late load must draw current frame');
  mode.value = 'always'; await mode.emit('change');
  mode.value = 'hover'; await mode.emit('change');
  assert(canvases.every(c => c.draws.at(-1).endsWith('frame-02.png')),'mode change while paused must preserve frame');
  assert.match(q('[data-frame-label]').textContent,/2 \/ 9/);
  await pause.emit('click');
  assert(canvases.every(c => c.draws.at(-1).endsWith('frame-01.png')),'resume hover resets inactive groups');
  const crowd = canvases.find(c => c.dataset.scene === 'original-bright' && c.dataset.actor === 'crowd');
  const smith = canvases.find(c => c.dataset.scene === 'original-bright' && c.dataset.actor === 'smith');
  await crowd.emit('focus');
  const hit = fixtures.find(f => f.frame === 0 && f.expected === 'smith');
  const pointer = {clientX:100+hit.x/2,clientY:50+hit.y/2};
  await h.scenes[0].stage.emit('pointermove', pointer);
  assert(crowd.classList.contains('is-highlighted') && smith.classList.contains('is-highlighted'));
  assert.equal(h.scenes[0].stage.style.cursor,'pointer');
  await h.scenes[0].stage.emit('click',pointer);
  assert(q('[data-inspector]').open);
  assert.equal(q('[data-dialog-gif]').src,data.clips.find(c => c.id === 'smith').gif);
  await q('[data-close]').emit('click');
  await crowd.emit('keydown',{key:'Enter'}); assert(q('[data-inspector]').open);
  await d.emit('keydown',{key:'Escape'}); assert(!q('[data-inspector]').open);
  h.frame(1); h.frame(161);
  await pause.emit('click'); const frozen = crowd.draws.at(-1);
  await crowd.emit('blur'); await h.scenes[0].stage.emit('pointerleave');
  assert.equal(crowd.draws.at(-1),frozen,'leave on pause must preserve frame');
  assert.equal(h.scenes[0].stage.style.cursor,'default');
  await d.querySelectorAll('[data-step]')[1].emit('click');
  assert(canvases.every(c => c.draws.length>0));
  await h.scenes[0].fullscreen.emit('click'); assert.equal(d.fullscreenElement,h.scenes[0].shell);
  await h.scenes[0].fullscreen.emit('click'); assert.equal(d.fullscreenElement,null);
  h.scenes[0].shell.requestFullscreen = async () => {throw new Error('unavailable');};
  await h.scenes[0].fullscreen.emit('click'); assert.match(q('[data-global-status]').textContent,/недоступен/);
  const failed = harness(); await failed.images[0].emit('error');
  assert(failed.scenes.every(s => !s.status.hidden));
  assert.match(failed.document.querySelector('[data-global-status]').textContent,/Не все файлы/);
  const html = fs.readFileSync(path.join(root,'gallery.html'),'utf8');
  assert.match(html,/\.stage-status\[hidden\]\{display:none\}/);
  const result = {status:'PASS',image_derived_hit_cases:fixtures.length, canvas_layers:16,
    scenarios:['late loading while paused','hover and keyboard focus together','scaled pointer coordinates',
      'click/Enter/Escape inspector','hover pause/leave/manual step/mode change','fullscreen shell/rejection','asset failure status'],
    browser_tested:false};
  fs.writeFileSync(path.join(report,'interaction-validation.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
})().catch(error => {console.error(error);process.exitCode=1;});
