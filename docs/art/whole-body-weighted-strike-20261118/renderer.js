"use strict";
(() => {
  const SLOT_NAMES = ["body", "weapon", "helmet"];
  const mod = (value, length) => ((value % length) + length) % length;
  const finite = (value, label) => {
    if (!Number.isFinite(value)) throw new Error(`Некорректное значение ${label}`);
    return value;
  };

  function sample(manifest, timeMs, mode = "auto") {
    finite(timeMs, "времени");
    const selected = mode === "auto" ? null : mode;
    if (selected && !manifest.clips[selected]) throw new Error(`Неизвестный режим ${selected}`);
    const clipName = selected || "idle";
    const clip = manifest.clips[clipName];
    const durations = clip.durations;
    if (!Array.isArray(durations) || durations.length === 0 || durations.some(d => !Number.isFinite(d) || d <= 0)) {
      throw new Error(`Некорректная длительность клипа ${clipName}`);
    }
    const duration = durations.reduce((a, b) => a + b, 0);
    // Auto показывает idle и затем attack; выбор экипировки не участвует в часах цикла.
    let localTime = mod(timeMs, duration);
    let activeClip = clipName;
    let cycle = Math.floor(timeMs / duration);
    if (mode === "auto" && manifest.clips.attack) {
      const idleDuration = manifest.clips.idle.durations.reduce((a, b) => a + b, 0);
      const attackDuration = manifest.clips.attack.durations.reduce((a, b) => a + b, 0);
      const fullDuration = idleDuration + attackDuration;
      localTime = mod(timeMs, fullDuration);
      cycle = Math.floor(timeMs / fullDuration);
      if (localTime >= idleDuration) {
        localTime -= idleDuration;
        activeClip = "attack";
      } else activeClip = "idle";
    }
    const active = manifest.clips[activeClip];
    let index = 0;
    while (index < active.durations.length - 1 && localTime >= active.durations[index]) {
      localTime -= active.durations[index];
      index += 1;
    }
    const socket = active.sockets[index];
    const root = socket.root === undefined ? [0, 0] : socket.root;
    if (!Array.isArray(root) || root.length !== 2 || !root.every(Number.isFinite)) throw new Error(`Некорректный root сокета ${activeClip}/${index}`);
    return { clip: activeClip, index, cycle, duration: active.durations[index], socket: { ...socket, root } };
  }

  function render(ctx, manifest, images, timeMs, options = {}) {
    if (manifest.canvas !== 256 || JSON.stringify(manifest.slots) !== JSON.stringify(SLOT_NAMES)) {
      throw new Error("Ожидается canvas 256 и слоты body/weapon/helmet");
    }
    const bodyNames = Object.keys(manifest.bodies);
    const bodyName = bodyNames.includes(options.body) ? options.body : bodyNames[0];
    const weaponName = options.weapon === "axe" ? "axe" : options.weapon === "none" ? "none" : "sword";
    const helmetName = options.helmet === "steel" ? "steel" : "none";
    const s = sample(manifest, timeMs, options.mode || "auto");
    const root = s.socket.root;
    const bodyPath = manifest.bodies?.[bodyName]?.[s.clip]?.[s.index];
    const weaponPath = weaponName === "none" ? null : manifest.equipment?.[weaponName]?.file;
    const helmetVariant = s.socket.helmetVariant === "profile" ? "profile" : "front";
    const helmetPath = helmetName === "none" ? null : manifest.equipment?.[`helmet_${helmetVariant}`]?.file;
    const ops = [];
    ctx.imageSmoothingEnabled = false;

    function image(path, label) {
      if (!path) throw new Error(`Нет пути изображения ${label}`);
      const img = images[path];
      if (!img || !img.complete || img.naturalWidth <= 0 || img.naturalHeight <= 0) throw new Error(`Изображение не загружено: ${path}`);
      return img;
    }
    function equipment(path, def, point, angle, scale, type, hidden) {
      if (!path || hidden) return;
      const img = image(path, type);
      const pivot = def.pivot;
      ctx.save();
      ctx.translate(point[0], point[1]);
      ctx.rotate(angle || 0);
      ctx.scale(scale || 1, scale || 1);
      // Окклюзия действует только на пиксели оружия у кисти; кадр цельного тела не маскируется.
      if (type === "weapon" && s.socket.gripRadius > 0) {
        ctx.beginPath();
        ctx.rect(-512, -512, 1024, 1024);
        ctx.arc(0, 0, s.socket.gripRadius, 0, Math.PI * 2);
        ctx.clip("evenodd");
      }
      ctx.drawImage(img, -pivot[0] * def.width, -pivot[1] * def.height, def.width, def.height);
      ctx.restore();
      ops.push({ type, path, x: point[0] + root[0], y: point[1] + root[1], angle: angle || 0, scale: scale || 1 });
    }
    function drawBody() {
      if (options.visible?.body === false) return;
      const img = image(bodyPath, "body");
      // Каждый вариант тела уже является полным RGBA кадром; он рисуется одним вызовом.
      ctx.drawImage(img, 0, 0, 256, 256);
      ops.push({ type: "body", path: bodyPath, x: root[0], y: root[1] });
    }
    const weaponVisible = options.visible?.weapon !== false;
    const helmetVisible = options.visible?.helmet !== false;
    const weaponDef = weaponName === "none" ? null : manifest.equipment[weaponName];
    const helmetDef = helmetPath ? manifest.equipment[`helmet_${helmetVariant}`] : null;
    ctx.save();
    ctx.translate(root[0], root[1]);
    try {
      if (s.socket.weaponBehind) equipment(weaponPath, weaponDef, s.socket.hand, s.socket.weaponAngle, 1, "weapon", !weaponVisible);
      drawBody();
      if (!s.socket.weaponBehind) equipment(weaponPath, weaponDef, s.socket.hand, s.socket.weaponAngle, 1, "weapon", !weaponVisible);
      if (helmetPath) equipment(helmetPath, helmetDef, s.socket.head, s.socket.headAngle, s.socket.headScale, "helmet", !helmetVisible);
      return { sample: s, ops };
    } finally {
      ctx.restore();
    }
  }

  window.FrameRig = { sample: (manifest, timeMs, mode = "auto") => sample(manifest, timeMs, mode), render };
})();
