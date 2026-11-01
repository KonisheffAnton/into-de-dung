"""Строит автономную галерею с PNG/GIF, встроенными прямо в HTML."""
from pathlib import Path
import base64
import json
import mimetypes

ROOT = Path(__file__).resolve().parent


def main() -> None:
    assets = {}

    def embed(path: Path) -> str:
        if not path.is_file():
            raise SystemExit(f"Missing gallery asset: {path}")
        key = path.relative_to(ROOT).as_posix()
        mime = mimetypes.guess_type(path.name)[0]
        if mime not in ("image/png", "image/gif"):
            raise SystemExit(f"Unexpected asset: {path}")
        assets[key] = f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"
        return key

    source = embed(ROOT / "model" / "source-full.png")
    initial = embed(ROOT / "model" / "input-256.png")
    clips = []
    for kind in ("idle", "death", "ability"):
        for variant in (1, 2, 3):
            folder = ROOT / "pixellab" / f"{kind}-{variant}"
            meta = json.loads((folder / "clip.json").read_text(encoding="utf-8"))
            if meta["actual_frames"] != 33 or len(meta["durations_ms"]) != 33:
                raise SystemExit(f"Incomplete clip: {folder}")
            clips.append({"key": meta["key"], "kind": kind, "variant": variant,
                          "count": meta["actual_frames"], "timing": meta["durations_ms"],
                          "loop": meta["loop"], "sheet": embed(folder / "spritesheet.png"),
                          "gif": embed(folder / "preview.gif"),
                          "margin": bool(meta["margin_violation_frames"]),
                          "last_equal": meta["last_frame_rgba_equal"]})

    template = r'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Разбойник 02 · PixelLab · 9 проб</title><style>
*{box-sizing:border-box}body{margin:0;background:#101723;color:#e8eef5;font:16px system-ui}header{padding:20px 26px;background:#1a2434;position:sticky;top:0;z-index:3}h1{margin:0 0 8px;font-size:24px}p{color:#bdc9d6;line-height:1.4}main{max-width:1400px;margin:auto;padding:18px}.controls{display:flex;gap:8px;flex-wrap:wrap;align-items:center}button,select{background:#2b3c54;border:1px solid #60718b;border-radius:6px;color:#fff;padding:7px 12px;cursor:pointer}.model{display:flex;align-items:center;gap:18px}.model img{width:180px;height:180px;object-fit:contain;background:#202b3d;image-rendering:pixelated}a{color:#edbe75}.grid{display:grid;grid-template-columns:repeat(3,minmax(220px,1fr));gap:13px}article{background:#1b2739;border:1px solid #34465e;border-radius:9px;padding:11px;text-align:center}article h3{margin:3px 0 9px}.stage{height:275px;display:grid;place-items:center;background:var(--stage,#182131)}canvas{width:256px;height:auto;max-width:100%;aspect-ratio:1;image-rendering:pixelated}body.game canvas{width:102px}body.zoom canvas{width:384px}body.zoom .stage{height:390px}input[type=range]{width:95%}.note{font-size:13px;color:#bac9dd}.warning{color:#ffbb88}.error{color:#ff9999}footer{padding:20px}@media(max-width:800px){header{position:static}.grid{grid-template-columns:1fr}.model{display:block}}
</style></head><body><header><h1>Разбойник 02 · девять проб PixelLab</h1><div class="controls"><button id="play">Пауза</button><button id="restart">Сначала</button><button id="step">+ кадр</button><select id="speed"><option value="1">Скорость 1×</option><option value="0.5">0,5×</option><option value="1.5">1,5×</option></select><select id="scale"><option value="">Размер 1×</option><option value="game">Игровой размер ~61 px</option><option value="zoom">Увеличить 1,5×</option></select><select id="background"><option value="#182131">Тёмный фон</option><option value="#88939c">Серый фон</option><option value="#ded4b9">Светлый фон</option></select></div></header><main><div class="model"><img id="input" alt="Подготовленная прозрачная модель"><div><p>Один образ, по три варианта ожидания, смерти и способности. Исходная поза и все кадры сохранены без ручной ретуши. Это просмотр проб, без подключения в игру.</p><p><a href="#" data-open="__SOURCE__">Полный прозрачный исходник</a> · <a href="#" data-open="__INITIAL__">Вход 256×256</a></p></div></div><div id="gallery"></div><p class="note">Смерть и способность проигрываются один раз и удерживают последний кадр. GIF повторяется при отдельном открытии. Швы цикла и конечные позы требуют художественного просмотра.</p></main><footer id="errors" class="error"></footer><script>
"use strict";const ASSETS=__ASSETS__;const CLIPS=__CLIPS__;const LABELS={idle:'Ожидание',death:'Смерть',ability:'Способность'};
const $=x=>document.querySelector(x);let players=[],playing=true,speed=1,last=0;
function openAsset(key){const data=ASSETS[key];if(!data){$('#errors').textContent='Встроенный файл не найден: '+key;return}const [head,b64]=data.split(',');const binary=atob(b64),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);const url=URL.createObjectURL(new Blob([bytes],{type:head.slice(5,-7)}));const a=document.createElement('a');a.href=url;a.target='_blank';a.rel='noopener';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),120000)}
document.addEventListener('click',e=>{const link=e.target.closest('[data-open]');if(link){e.preventDefault();openAsset(link.dataset.open)}});
$('#input').src=ASSETS['__INITIAL__'];$('#input').onerror=()=>$('#errors').textContent='Не удалось загрузить встроенный входной PNG';
for(const kind of ['idle','death','ability']){let html=`<h2>${LABELS[kind]}</h2><div class="grid">`;for(const c of CLIPS.filter(x=>x.kind===kind)){const i=players.length;players.push({c,frame:0,elapsed:0,img:new Image(),loaded:false});html+=`<article><h3>${LABELS[kind]} ${c.variant}</h3><div class="stage"><canvas width="256" height="256" data-canvas="${i}"></canvas></div><input type="range" min="0" max="${c.count-1}" value="0" data-slider="${i}"><p class="note">${c.count} кадров · ${c.loop?'цикл':'одно исполнение'}${c.margin?' · <span class="warning">выход в крайний отступ</span>':''}</p><p><a href="#" data-open="${c.gif}">GIF</a> · <a href="#" data-open="${c.sheet}">PNG-лист</a></p><div class="error" data-error="${i}"></div></article>`}$('#gallery').insertAdjacentHTML('beforeend',html+'</div>')}
players.forEach((p,i)=>{p.canvas=document.querySelector(`[data-canvas="${i}"]`);p.slider=document.querySelector(`[data-slider="${i}"]`);p.slider.oninput=()=>{playing=false;$('#play').textContent='Играть';p.frame=+p.slider.value;p.elapsed=0;draw(p)};p.img.onload=()=>{p.loaded=true;draw(p)};p.img.onerror=()=>document.querySelector(`[data-error="${i}"]`).textContent='Не удалось загрузить встроенный PNG-лист';p.img.src=ASSETS[p.c.sheet]});
function draw(p){if(!p.loaded)return;const ctx=p.canvas.getContext('2d');ctx.clearRect(0,0,256,256);ctx.drawImage(p.img,p.frame%8*256,Math.floor(p.frame/8)*256,256,256,0,0,256,256);p.slider.value=p.frame}
function tick(t){if(!last)last=t;const dt=Math.min(100,t-last);last=t;if(playing)for(const p of players){if(!p.loaded)continue;p.elapsed+=dt*speed;let duration=p.c.timing[p.frame];while(p.elapsed>=duration){p.elapsed-=duration;if(p.frame<p.c.count-1)p.frame++;else if(p.c.loop)p.frame=0;else{p.elapsed=0;break}duration=p.c.timing[p.frame]}draw(p)}requestAnimationFrame(tick)}
$('#play').onclick=()=>{playing=!playing;$('#play').textContent=playing?'Пауза':'Играть'};$('#restart').onclick=()=>{for(const p of players){p.frame=0;p.elapsed=0;draw(p)}playing=true;$('#play').textContent='Пауза'};$('#step').onclick=()=>{playing=false;$('#play').textContent='Играть';for(const p of players){p.frame=Math.min(p.frame+1,p.c.count-1);draw(p)}};$('#speed').onchange=e=>speed=+e.target.value;$('#scale').onchange=e=>document.body.className=e.target.value;$('#background').onchange=e=>document.documentElement.style.setProperty('--stage',e.target.value);requestAnimationFrame(tick);
</script></body></html>'''
    html = (template.replace("__ASSETS__", json.dumps(assets, separators=(",", ":")))
            .replace("__CLIPS__", json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
            .replace("__SOURCE__", source).replace("__INITIAL__", initial))
    output = ROOT / "gallery.html"
    output.write_text(html, encoding="utf-8")
    print(json.dumps({"clips": len(clips), "embedded_assets": len(assets), "html_bytes": output.stat().st_size}))


if __name__ == "__main__":
    main()
