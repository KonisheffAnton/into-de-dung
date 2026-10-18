(() => {
  "use strict";

  const INTERACTION = window.DioramaInteraction;
  const DATA = window.DIORAMA_LAYER_DATA;
  const FRAME_COUNT = 9;
  const WIDTH = 1672;
  const HEIGHT = 941;
  const clips = new Map();
  const sceneStates = new Map();
  const focusGroups = new Set();
  const hoverGroups = new Set();
  let mode = "always";
  let paused = false;
  let lastTick = 0;
  let pending = 0;
  let loadFailed = false;
  const globalStatus = document.querySelector("[data-global-status]");
  const frameLabel = document.querySelector("[data-frame-label]");
  const stepButtons = document.querySelectorAll("[data-step]");
  const inspector = document.querySelector("[data-inspector]");

  function updateLoadStatus() {
    const stageStatuses = document.querySelectorAll(".stage-status");
    if (loadFailed) {
      globalStatus.textContent = "Не все файлы предпросмотра доступны. Проверьте, что материалы находятся рядом с этой страницей.";
      stageStatuses.forEach((status) => {
        status.textContent = "Не удалось загрузить часть слоёв.";
        status.hidden = false;
      });
    } else if (pending > 0) {
      globalStatus.textContent = "Загружаем сцены и выбранные анимации…";
      stageStatuses.forEach((status) => {
        status.textContent = "Загружаем фон и выбранные анимации…";
        status.hidden = false;
      });
    } else {
      globalStatus.textContent = "Сцены готовы. Персонажи перемещаются отдельными слоями поверх неизменённого фона.";
      stageStatuses.forEach((status) => { status.hidden = true; });
    }
  }

  function trackImage(image) {
    pending += 1;
    image.addEventListener("load", () => {
      pending -= 1;
      updateLoadStatus();
    }, { once: true });
    image.addEventListener("error", () => {
      pending -= 1;
      loadFailed = true;
      updateLoadStatus();
    }, { once: true });
  }

  function sceneGroupKey(sceneId, group) {
    return `${sceneId}:${group}`;
  }

  function getState(sceneId, group) {
    const key = sceneGroupKey(sceneId, group);
    if (!sceneStates.has(key)) sceneStates.set(key, { sceneId, group, frame: 0, elapsed: 0 });
    return sceneStates.get(key);
  }

  function groupActive(key) {
    return mode === "always" || hoverGroups.has(key) || focusGroups.has(key);
  }

  function setGroupPresence(key, collection, isActive) {
    if (isActive) collection.add(key);
    else collection.delete(key);
    if (!paused && mode === "hover" && !hoverGroups.has(key) && !focusGroups.has(key)) {
      const state = sceneStates.get(key);
      if (state) {
        state.frame = 0;
        state.elapsed = 0;
        drawSceneGroup(state.sceneId, state.group);
      }
    }
  }

  function maskFor(group, frameIndex) {
    const clip = clips.get(group);
    return clip ? clip.masks[frameIndex] : null;
  }

  function currentFrameMap(sceneId) {
    const frames = {};
    for (const clip of DATA.clips) frames[clip.id] = getState(sceneId, clip.id).frame;
    return frames;
  }

  function drawCanvas(canvas, actor, groupFrame) {
    const clip = clips.get(actor.group);
    if (!clip) return;
    const image = clip.images[groupFrame];
    if (!image || !image.complete || image.naturalWidth === 0) return;
    const [sx, sy, sw, sh] = actor.source;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.imageSmoothingEnabled = false;
    if (actor.flipX) {
      ctx.save();
      ctx.translate(sw, 0);
      ctx.scale(-1, 1);
      ctx.drawImage(image, sx, sy, sw, sh, 0, 0, sw, sh);
      ctx.restore();
    } else {
      ctx.drawImage(image, sx, sy, sw, sh, 0, 0, sw, sh);
    }
  }

  function drawSceneGroup(sceneId, group) {
    const state = getState(sceneId, group);
    document.querySelectorAll(".actor-canvas").forEach((canvas) => {
      if (canvas.dataset.scene === sceneId && canvas.dataset.group === group) drawCanvas(canvas, canvas.actorData, state.frame);
    });
  }

  function drawGroupAcrossScenes(group) {
    for (const state of sceneStates.values()) {
      if (state.group === group) drawSceneGroup(state.sceneId, group);
    }
  }

  function setHighlight(sceneId) {
    document.querySelectorAll(".actor-canvas").forEach((canvas) => {
      if (canvas.dataset.scene !== sceneId) return;
      const key = sceneGroupKey(sceneId, canvas.dataset.group);
      canvas.classList.toggle("is-highlighted", hoverGroups.has(key) || focusGroups.has(key));
    });
  }

  function createActor(scene, actor) {
    const [sx, sy, sw, sh] = actor.source;
    const [dx, dy, dw, dh] = actor.destination;
    const canvas = document.createElement("canvas");
    canvas.className = "actor-canvas";
    canvas.width = sw;
    canvas.height = sh;
    canvas.tabIndex = 0;
    canvas.setAttribute("role", "button");
    canvas.setAttribute("aria-label", `${actor.label} · нажмите, чтобы рассмотреть анимацию`);
    canvas.dataset.scene = scene.id;
    canvas.dataset.group = actor.group;
    canvas.dataset.actor = actor.id;
    canvas.dataset.z = String(actor.z);
    canvas.style.left = `${dx / WIDTH * 100}%`;
    canvas.style.top = `${dy / HEIGHT * 100}%`;
    canvas.style.width = `${dw / WIDTH * 100}%`;
    canvas.style.height = `${dh / HEIGHT * 100}%`;
    canvas.actorData = actor;
    canvas.addEventListener("focus", () => {
      const key = sceneGroupKey(scene.id, actor.group);
      setGroupPresence(key, focusGroups, true);
      setHighlight(scene.id);
    });
    canvas.addEventListener("blur", () => {
      const key = sceneGroupKey(scene.id, actor.group);
      setGroupPresence(key, focusGroups, false);
      setHighlight(scene.id);
    });
    canvas.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        showInspector(actor.group);
      }
    });
    scene.stage.append(canvas);
    drawCanvas(canvas, actor, getState(scene.id, actor.group).frame);
    return canvas;
  }

  function worldPoint(stage, event) {
    const rect = stage.getBoundingClientRect();
    return { x: (event.clientX - rect.left) / rect.width * WIDTH,
      y: (event.clientY - rect.top) / rect.height * HEIGHT };
  }

  function hitActor(scene, event) {
    const point = worldPoint(scene.stage, event);
    const frames = currentFrameMap(scene.id);
    return INTERACTION.hitTest(DATA.actors, point.x, point.y,
      Object.fromEntries(Array.from(clips, ([id, clip]) => [id, clip.masks])), frames,
      DATA.foregroundZ, DATA.occlusionPolygons);
  }

  function updatePointer(scene, event) {
    const actor = hitActor(scene, event);
    scene.stage.style.cursor = actor ? "pointer" : "default";
    const previous = scene.hoveredGroup;
    const next = actor ? actor.group : null;
    if (previous === next) return;
    if (previous) {
      const previousKey = sceneGroupKey(scene.id, previous);
      setGroupPresence(previousKey, hoverGroups, false);
      setHighlight(scene.id);
    }
    scene.hoveredGroup = next;
    if (next) {
      const key = sceneGroupKey(scene.id, next);
      setGroupPresence(key, hoverGroups, true);
      setHighlight(scene.id);
    }
  }

  function showInspector(group) {
    const clip = clips.get(group);
    if (!clip) return;
    document.querySelector("[data-dialog-title]").textContent = clip.title;
    const image = document.querySelector("[data-dialog-gif]");
    const link = document.querySelector("[data-dialog-link]");
    image.src = clip.gif;
    link.href = clip.gif;
    if (!inspector.open) inspector.showModal();
  }

  function addSceneLinks(scene, background) {
    const container = scene.element.querySelector(".scene-links");
    const sourceHref = background.source.startsWith("docs/art/")
      ? `../${background.source.slice("docs/art/".length)}` : background.source;
    const sourceLink = document.createElement("a");
    sourceLink.href = sourceHref;
    sourceLink.target = "_blank";
    sourceLink.rel = "noopener";
    sourceLink.textContent = "Открыть исходный фон ↗";
    const placementLink = document.createElement("a");
    placementLink.href = "placement.json";
    placementLink.target = "_blank";
    placementLink.rel = "noopener";
    placementLink.textContent = "Данные размещения ↗";
    container.append(sourceLink, placementLink);
  }

  function setupScene(background) {
    const element = Array.from(document.querySelectorAll(".scene")).find((node) => node.dataset.scene === background.id);
    if (!element) throw new Error(`Unknown scene ${background.id}`);
    const stage = element.querySelector(".stage");
    const bg = element.querySelector(".background");
    trackImage(bg);
    bg.src = background.file;
    let foreground = null;
    if (background.foreground) {
      foreground = document.createElement("img");
      foreground.className = "foreground";
      foreground.alt = "";
      stage.insertBefore(foreground, stage.querySelector(".stage-status"));
      trackImage(foreground);
      foreground.src = background.foreground;
    }
    const scene = { id: background.id, element, stage, hoveredGroup: null, foreground };
    const fullscreenShell = element.querySelector(".stage-shell");
    const fullscreenButton = element.querySelector("[data-fullscreen]");
    const updateFullscreenLabel = () => {
      fullscreenButton.textContent = document.fullscreenElement === fullscreenShell ? "Выйти из полного экрана" : "На весь экран";
    };
    fullscreenButton.addEventListener("click", async () => {
      try {
        if (document.fullscreenElement === fullscreenShell) {
          await document.exitFullscreen();
        } else if (fullscreenShell.requestFullscreen) {
          await fullscreenShell.requestFullscreen();
        }
      } catch (error) {
        globalStatus.textContent = "Полноэкранный просмотр сейчас недоступен.";
      }
    });
    document.addEventListener("fullscreenchange", updateFullscreenLabel);
    stage.addEventListener("pointermove", (event) => updatePointer(scene, event));
    stage.addEventListener("pointerleave", () => updatePointer(scene, { clientX: -1e6, clientY: -1e6 }));
    stage.addEventListener("click", (event) => {
      const actor = hitActor(scene, event);
      if (actor) showInspector(actor.group);
    });
    for (const actor of DATA.actors.slice().sort((a, b) => a.z - b.z)) createActor(scene, actor);
    addSceneLinks(scene, background);
    return scene;
  }

  function setupSelected() {
    const list = document.querySelector("[data-selected]");
    for (const clip of DATA.clips) {
      const card = document.createElement("article");
      card.className = "selected-card";
      const label = document.createElement("span");
      label.className = "eyebrow";
      label.textContent = clip.title;
      const link = document.createElement("a");
      link.href = clip.gif;
      link.target = "_blank";
      link.rel = "noopener";
      link.textContent = "Открыть выбранную анимацию ↗";
      card.append(label, link);
      list.append(card);
    }
  }

  function decodeMask(encoded) {
    const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
    if (bytes.length !== 8192) throw new Error("Invalid actor alpha mask size");
    return bytes;
  }

  if (!INTERACTION || !DATA) {
    globalStatus.textContent = "Данные предпросмотра ещё не готовы.";
    return;
  }

  for (const clip of DATA.clips) {
    const images = clip.frames.map((frame) => {
      const image = new Image();
      trackImage(image);
      image.addEventListener("load", () => drawGroupAcrossScenes(clip.id), { once: true });
      image.src = frame.file;
      return image;
    });
    clips.set(clip.id, { ...clip, images, masks: clip.masks.map(decodeMask) });
  }
  DATA.backgrounds.forEach(setupScene);
  setupSelected();

  document.querySelector("[data-mode]").addEventListener("change", (event) => {
    mode = event.currentTarget.value;
    if (!paused) {
      for (const state of sceneStates.values()) {
        state.elapsed = 0;
        state.frame = 0;
        drawSceneGroup(state.sceneId, state.group);
      }
    }
    updateFrameLabel();
  });
  document.querySelector("[data-pause]").addEventListener("click", (event) => {
    paused = !paused;
    event.currentTarget.textContent = paused ? "Продолжить" : "Пауза";
    event.currentTarget.setAttribute("aria-pressed", String(paused));
    stepButtons.forEach((button) => { button.disabled = !paused; });
    if (!paused && mode === "hover") {
      for (const state of sceneStates.values()) {
        const key = sceneGroupKey(state.sceneId, state.group);
        if (hoverGroups.has(key) || focusGroups.has(key)) continue;
        state.frame = 0;
        state.elapsed = 0;
        drawSceneGroup(state.sceneId, state.group);
      }
    }
  });
  stepButtons.forEach((button) => button.addEventListener("click", () => {
    if (!paused) return;
    const step = Number(button.dataset.step);
    for (const state of sceneStates.values()) {
      state.frame = (state.frame + step + FRAME_COUNT) % FRAME_COUNT;
      state.elapsed = 0;
      drawSceneGroup(state.sceneId, state.group);
    }
    updateFrameLabel();
  }));
  document.querySelector("[data-close]").addEventListener("click", () => inspector.close());
  inspector.addEventListener("click", (event) => { if (event.target === inspector) inspector.close(); });
  document.addEventListener("keydown", (event) => { if (event.key === "Escape" && inspector.open) inspector.close(); });

  function updateFrameLabel() {
    const active = Array.from(sceneStates.values()).find((state) => groupActive(sceneGroupKey(state.sceneId, state.group)));
    const displayed = active || sceneStates.values().next().value;
    frameLabel.textContent = `Кадр ${(displayed ? displayed.frame : 0) + 1} / ${FRAME_COUNT}`;
  }

  function tick(time) {
    if (lastTick === 0) lastTick = time;
    const delta = Math.min(time - lastTick, 1000);
    lastTick = time;
    if (!paused) {
      for (const state of sceneStates.values()) {
        const key = sceneGroupKey(state.sceneId, state.group);
        if (!groupActive(key)) continue;
        const clip = clips.get(state.group);
        state.elapsed += delta;
        while (state.elapsed >= clip.frameMs) {
          state.elapsed -= clip.frameMs;
          state.frame = (state.frame + 1) % FRAME_COUNT;
          drawSceneGroup(state.sceneId, state.group);
        }
      }
      updateFrameLabel();
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
