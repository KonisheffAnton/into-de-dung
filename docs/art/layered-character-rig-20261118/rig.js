"use strict";
(() => {
  const TAU = Math.PI * 2;
  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  const smooth = (v) => { const t = clamp01(v); return t * t * (3 - 2 * t); };

  // Оснастка получает один фазовый параметр: экипировка меняет только набор картинок.
  function pose(timeMs, mode = "auto") {
    const cycle = ((timeMs % 5000) + 5000) % 5000;
    const breath = Math.sin((mode === "strike" ? timeMs : cycle) * TAU / 2500);
    const track = [[0, .20, -.30, -.035], [.24, -2.05, -.40, .10], [.36, -2.05, -.40, .10], [.46, -1.25, .50, -.20], [.60, -1.05, .65, -.12], [1, .20, -.30, -.035]];
    let u = 0;
    if (mode === "strike") u = ((timeMs % 2000) + 2000) % 2000 / 2000;
    else if (mode === "auto" && cycle >= 2000 && cycle <= 4000) u = (cycle - 2000) / 2000;
    let nearUpper = .20, nearFore = -.30, torsoLean = -.035;
    for (let i = 0; i < track.length - 1; i++) {
      const a = track[i], b = track[i + 1];
      if (u >= a[0] && u <= b[0]) {
        const t = smooth((u - a[0]) / (b[0] - a[0]));
        nearUpper = a[1] + (b[1] - a[1]) * t;
        nearFore = a[2] + (b[2] - a[2]) * t;
        torsoLean = a[3] + (b[3] - a[3]) * t;
        break;
      }
    }
    const bob = breath * 1.6;
    const lift = Math.max(0, (.20 - nearUpper) / 2.25);
    const swing = Math.max(0, Math.min(1, (nearUpper + 2.05) / .8));
    return {
      timeMs, mode, cycle, breath, lift, swing,
      root: { x: 128, y: 212 + bob },
      torso: { rotation: torsoLean, rise: bob },
      head: { rotation: -torsoLean * .45 },
      legs: { left: -0.035 - breath * .012, right: 0.035 + breath * .012 },
      arms: {
        far: { upper: -0.10 - lift * .12, fore: 0.18 + lift * .08 },
        near: { upper: nearUpper, fore: nearFore }
      }
    };
  }

  function render(ctx, manifest, images, timeMs, options = {}) {
    const selected = pose(timeMs, options.mode || "auto");
    const armor = options.armor === "heavy" ? "heavy" : "light";
    const weapon = options.weapon === "axe" ? "axe" : "sword";
    const showArmor = options.showArmor !== false, showWeapon = options.showWeapon !== false;
    const explode = Number(options.explode || 0), joints = options.joints === true || options.showBones === true;
    ctx.imageSmoothingEnabled = false;
    const ops = [];
    const parts = manifest.parts;
    const imageFor = (key) => images[key];
    const draw = (key, x, y, rotation = 0, group = "body", offsetX = 0, offsetY = 0) => {
      const def = parts[key], img = imageFor(key);
      if (!def || !img || !img.complete) return null;
      const px = def.pivot[0] * def.width, py = def.pivot[1] * def.height;
      const dx = Math.cos(rotation) * offsetX - Math.sin(rotation) * offsetY;
      const dy = Math.sin(rotation) * offsetX + Math.cos(rotation) * offsetY;
      ctx.save(); ctx.translate(x + dx, y + dy); ctx.rotate(rotation);
      if (def.flip_x === true) ctx.scale(-1, 1);
      ctx.drawImage(img, -px, -py, def.width, def.height); ctx.restore();
      const op = { key, x: x + dx, y: y + dy, rotation, group }; ops.push(op); return op;
    };
    const root = selected.root;
    const hip = { x: root.x, y: root.y - 34 };
    const torsoRot = selected.torso.rotation;
    const torsoAnchor = { x: hip.x, y: hip.y - 2 };
    const point = (origin, dx, dy, angle) => ({ x: origin.x + Math.cos(angle) * dx - Math.sin(angle) * dy, y: origin.y + Math.sin(angle) * dx + Math.cos(angle) * dy });
    const local = (dx, dy) => point(torsoAnchor, dx, dy, torsoRot);
    const farHip = {x: hip.x - 8, y: hip.y}, nearHip = {x: hip.x + 8, y: hip.y};
    draw("leg_left", farHip.x, farHip.y, selected.legs.left, "body", -explode, 0);
    draw("leg_right", nearHip.x, nearHip.y, selected.legs.right, "body", explode, 0);
    draw("pelvis", hip.x, hip.y + explode, torsoRot, "body");
    draw("torso", torsoAnchor.x, torsoAnchor.y, torsoRot, "body");
    const headAt = local(0, -60);
    if (showArmor) draw(armor === "heavy" ? "armor_heavy" : "armor_light", torsoAnchor.x + 3 * explode, torsoAnchor.y, torsoRot, "armor");
    {
      const def = parts.torso, img = imageFor("torso"), collarHeight = Math.min(20, def.height);
      if (img && img.complete) {
        // Шарф остаётся на шее поверх нагрудника, чтобы голова не теряла связь с телом.
        ctx.save(); ctx.translate(torsoAnchor.x, torsoAnchor.y); ctx.rotate(torsoRot);
        ctx.drawImage(img, 0, 0, def.width, collarHeight, -def.pivot[0] * def.width, -def.pivot[1] * def.height, def.width, collarHeight);
        ctx.restore();
        ops.push({ key: "torso_collar", x: torsoAnchor.x, y: torsoAnchor.y, rotation: torsoRot, group: "body" });
      }
    }
    draw("head", headAt.x, headAt.y - 2 * explode, selected.head.rotation + torsoRot, "body");
    const arm = (side) => {
      const isNear = side === "near", spec = selected.arms[side];
      const shoulder = local(isNear ? 21 : -21, -51);
      const upperAngle = torsoRot + spec.upper;
      const elbow = point(shoulder, 0, 28, upperAngle);
      const foreAngle = upperAngle + spec.fore;
      const wrist = point(elbow, 0, 25, foreAngle);
      const explodeSide = (isNear ? 1 : -1) * explode;
      draw("upper_arm", shoulder.x, shoulder.y, upperAngle, "body", explodeSide, 0);
      if (showArmor) draw(armor === "heavy" ? "shoulder_heavy" : "shoulder_light", shoulder.x, shoulder.y, upperAngle, "armor", explodeSide * 1.35, -explode * .25);
      draw("forearm", elbow.x, elbow.y, foreAngle, "body", explodeSide, 0);
      if (showArmor) draw(armor === "heavy" ? "bracer_heavy" : "bracer_light", elbow.x, elbow.y, foreAngle, "armor", explodeSide * 1.35, -explode * .25);
      if (isNear && showWeapon) draw(weapon, wrist.x + 3 * explode, wrist.y, foreAngle + 2.3, "weapon");
      draw("hand", wrist.x, wrist.y, foreAngle, "body");
      if (joints) { ctx.fillStyle = "#ffde59"; for (const p of [shoulder, elbow, wrist]) { ctx.fillRect(Math.round(p.x)-2, Math.round(p.y)-2, 4, 4); } }
    };
    arm("far"); arm("near");
    return { ...selected, armor, weapon, ops };
  }

  window.LayeredRig = { pose, render };
  window.__rigQA = { pose, render };
  window.renderPreview = function(timeMs, options = {}) {
    const canvases = options.canvases || [...document.querySelectorAll("canvas[data-rig]")];
    const results = [];
    for (const canvas of canvases) {
      const ctx = canvas.getContext("2d"); ctx.clearRect(0, 0, canvas.width, canvas.height);
      const data = window.__rigAssets;
      if (data) {
        const isMain = canvas.id === "hero";
        results.push(render(ctx, data.manifest, data.images, timeMs, { ...options, armor: isMain ? (options.armor || "light") : (canvas.dataset.armor || "light"), weapon: isMain ? (options.weapon || "sword") : (canvas.dataset.weapon || "sword") }));
      }
    }
    return results;
  };
})();
