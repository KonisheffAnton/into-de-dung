const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const sharp = require(process.env.SHARP_MODULE || 'sharp');

const root = __dirname;
const rig = JSON.parse(fs.readFileSync(path.join(root, 'rig.json'), 'utf8'));
const hash = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const tracked = [
  path.resolve(root, '../../../assets/art_presets/approved/grass_defender_v1/grass_reference_v1.png'),
  path.resolve(root, '../../../assets/art_presets/approved/grass_defender_v1/defender_reference_v1.png'),
  ...rig.variants.map((variant) => path.join(root, variant.atlas))
];
const sourceHashesBefore = Object.fromEntries(tracked.map((file) => [path.relative(root, file).replaceAll('\\', '/'), hash(fs.readFileSync(file))]));

(async () => {
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 960 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    await page.goto(pathToFileURL(path.join(root, 'preview.html')).href + '?test=1');
    await page.evaluate(() => window.ready);
    await page.evaluate(() => window.preview.setPlaying(false));
    await page.evaluate(() => window.preview.renderAt(0));
    await page.screenshot({ path: path.join(root, 'preview.png'), fullPage: true });
    await page.evaluate(() => window.preview.renderAt(1600));
    await page.screenshot({ path: path.join(root, 'phase-1600.png'), fullPage: true });
    await page.evaluate(() => window.preview.setExploded(true));
    await page.screenshot({ path: path.join(root, 'parts.png'), fullPage: true });
    await page.evaluate(() => window.preview.setExploded(false));

    const period = rig.period_ms;
    const frameBuffers = [];
    const frameHashes = [];
    for (let frame = 0; frame < 32; frame += 1) {
      await page.evaluate((ms) => window.preview.renderAt(ms), frame * 100);
      const dataUrl = await page.evaluate(() => window.preview.exportFrame());
      const buffer = Buffer.from(dataUrl.slice('data:image/png;base64,'.length), 'base64');
      frameBuffers.push(buffer);
      frameHashes.push(hash(buffer));
    }
    await page.evaluate((ms) => window.preview.renderAt(ms), period);
    const atPeriod = await page.evaluate(() => window.preview.exportFrame());
    const atZero = await page.evaluate(() => { window.preview.renderAt(0); return window.preview.exportFrame(); });
    const loopPixelsEqual = atPeriod === atZero;

    const pixelProbe = async (ms, region) => page.evaluate(({ time, area }) => {
      window.preview.renderAt(time);
      const canvas = document.getElementById('comparison');
      const ctx = canvas.getContext('2d');
      return Array.from(ctx.getImageData(area.x, area.y, area.width, area.height).data);
    }, { time: ms, area: region });
    const anchors = [];
    const staticGround = [];
    for (let i = 0; i < rig.variants.length; i += 1) {
      const variant = rig.variants[i];
      const legs = variant.layers.find((layer) => layer.id === 'legs');
      if (!legs || legs.amplitude_y !== 0) throw new Error(`Feet anchor invalid: ${variant.id} legs amplitude_y must be 0`);
      const [sx, sy, sw, sh] = legs.crop;
      // Маска нижней четверти ног проверяет подошвы, исключая перекрываемые щитом голени.
      const footCheck = await page.evaluate(({index,variant,period})=>{
        const c=document.getElementById('comparison');
        const mask=document.createElement('canvas');mask.width=c.width;mask.height=c.height;
        const mc=mask.getContext('2d');mc.imageSmoothingEnabled=false;mc.scale(4,4);
        const leg=variant.layers.find(l=>l.id==='legs'),[sx,sy,sw,sh]=leg.crop;
        const cx=(index+1)*128+64,cy=72;
        const cached=layerCache[variant.id+'-legs-4'];
        mc.drawImage(cached,cx+Math.round(leg.position[0]*4)/4,cy+Math.round(leg.position[1]*4)/4,cached.width/4,cached.height/4);
        const alpha=mc.getImageData(0,0,c.width,c.height).data;
        const minY=Math.ceil((cy+leg.position[1]+sh*leg.scale*.75)*4),offsets=[];
        for(let y=minY;y<c.height;y++)for(let x=0;x<c.width;x++){
          const off=(y*c.width+x)*4;if(alpha[off+3]>=128)offsets.push(off);
        }
        let base=null,unchanged=true;
        for(let f=0;f<32;f++){
          window.preview.renderAt(f*period/32);
          const pixels=c.getContext('2d').getImageData(0,0,c.width,c.height).data;
          const values=offsets.flatMap(o=>[pixels[o],pixels[o+1],pixels[o+2],pixels[o+3]]);
          if(base===null)base=values;else if(values.some((v,j)=>v!==base[j]))unchanged=false;
        }
        return {sampled_opaque_pixels:offsets.length,frames:32,unchanged};
      },{index:i,variant,period});
      anchors.push({variant:variant.id,...footCheck});
      const tileRegion = { x: (i+1)*512+80, y: 364, width: 350, height: 132 };
      const ground0 = await pixelProbe(0, tileRegion);
      const ground1 = await pixelProbe(period * 0.375, tileRegion);
      staticGround.push({ variant: variant.id, region: tileRegion, unchanged: JSON.stringify(ground0) === JSON.stringify(ground1) });
    }

    const frame0 = frameBuffers[0];
    const frameMid = frameBuffers[8];
    const diff = await sharp(frame0).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const other = await sharp(frameMid).ensureAlpha().raw().toBuffer();
    let changedPixels = 0;
    for (let p = 0; p < diff.data.length; p += diff.info.channels) {
      if (diff.data[p]!==other[p] || diff.data[p+1]!==other[p+1] || diff.data[p+2]!==other[p+2]) changedPixels += 1;
    }

    const controlResults = await page.evaluate(() => {
      document.getElementById('restart').click();
      const restart = window.preview.getState().time === 0;
      document.getElementById('speed').value = '2';
      document.getElementById('speed').dispatchEvent(new Event('change'));
      const speed = window.preview.getState().speed === 2;
      document.getElementById('exploded').click();
      const exploded = window.preview.getState().exploded === true;
      document.getElementById('phase').value = '1000';
      document.getElementById('phase').dispatchEvent(new Event('input'));
      const phase = Math.round(window.preview.getState().time) === 1000;
      document.getElementById('toggle').click();
      const pausePlay = window.preview.getState().playing === true;
      window.preview.setPlaying(false);
      window.preview.setExploded(false);
      return { restart, speed, exploded, phase, pausePlay };
    });

    const gifWidth = 1536;
    const gifHeight = 652;
    const { data: stacked, info } = await sharp({ create: { width: gifWidth, height: gifHeight * frameBuffers.length, channels: 4, background: '#11171d' } })
      .composite(await Promise.all(frameBuffers.map(async (buffer, i) => ({ input: await sharp(buffer).resize(gifWidth, gifHeight, { kernel: 'nearest' }).png().toBuffer(), left: 0, top: i * gifHeight }))))
      .raw().toBuffer({ resolveWithObject: true });
    // У вертикального стека задаём высоту страницы, чтобы sharp прочитал каждую полосу как кадр GIF.
    await sharp(stacked, { raw: { width: info.width, height: info.height, channels: info.channels, pageHeight: gifHeight } })
      .gif({ loop: 0, delay: Array(32).fill(100) }).toFile(path.join(root, 'idle.gif'));
    const gifMeta=await sharp(path.join(root,'idle.gif'),{animated:true}).metadata();

    const sourceHashesAfter = Object.fromEntries(tracked.map((file) => [path.relative(root, file).replaceAll('\\', '/'), hash(fs.readFileSync(file))]));
    const sourceChecks = Object.keys(sourceHashesBefore).map((file) => ({ file, unchanged: sourceHashesBefore[file] === sourceHashesAfter[file], sha256: sourceHashesBefore[file] }));
    const checks = {
      loop_pixel_identity: loopPixelsEqual,
      frame_difference_pixel_count: changedPixels,
      feet_anchor_checks: anchors,
      ground_tile_checks: staticGround,
      controls: controlResults,
      frame_count: frameBuffers.length,
      frame_interval_ms: 100,
      gif:{pages:gifMeta.pages,pageHeight:gifMeta.pageHeight,loop:gifMeta.loop,delay:gifMeta.delay},
      source_hashes: sourceChecks,
      javascript_errors: errors
    };
    // GIF может объединить одинаковые соседние кадры; длительность цикла обязана сохраниться.
    const failures = !loopPixelsEqual || changedPixels === 0 || anchors.some((entry) => !entry.unchanged||entry.sampled_opaque_pixels===0) || staticGround.some((entry) => !entry.unchanged) || Object.values(controlResults).some((value) => !value) || sourceChecks.some((entry) => !entry.unchanged) || gifMeta.pages<2 || gifMeta.pages>32 || gifMeta.delay.reduce((a,b)=>a+b,0)!==period || errors.length;
    const result = {
      status: failures ? 'FAIL' : 'PASS',
      checks,
      scope: 'Offline HTML/Canvas renderer, deterministic cycle, visible frame changes, controls and source-byte integrity. No Godot/runtime, F5, DPI/GPU or art acceptance claim.'
    };
    fs.writeFileSync(path.join(root, 'validation.json'), JSON.stringify(result, null, 2) + '\n');
    if (failures) throw new Error(`Preview validation failed; see ${path.join(root, 'validation.json')}`);
    console.log(JSON.stringify(result));
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
