(() => {
  "use strict";

  const TITLES = ["Ровный удар", "Тяжёлый удар", "Короткий удар", "Плавный возврат", "Точный удар"];
  const cards = [];
  const base = location.href;
  const frameMilliseconds = 160;
  let globalPlaying = true;
  let lastTick = 0;
  const asset = (path) => new URL(path, base).href;

  function makeCard(index, title) {
    const folder = `animations/smith-${String(index + 1).padStart(2, "0")}`;
    const card = document.createElement("article");
    card.className = "variant";
    card.innerHTML = `<div class="card-head"><div><span class="eyebrow">Вариант ${String(index + 1).padStart(2, "0")}</span><h3></h3></div><output class="counter">01 / 09</output></div>
      <div class="stage checker"><canvas width="256" height="256" aria-label="Кадр анимации"></canvas><span class="missing" hidden>Кадры ещё не добавлены</span></div>
      <p class="phase" aria-live="off"></p>
      <input class="scrub" type="range" min="0" max="8" step="1" value="0" aria-label="Выбор кадра">
      <div class="transport"><button type="button" class="prev" aria-label="Предыдущий кадр">◀</button><button type="button" class="toggle">Пауза</button><button type="button" class="next" aria-label="Следующий кадр">▶</button></div>
      <div class="asset-links sources"><a class="gif" target="_blank" rel="noopener">GIF</a><a class="contact" target="_blank" rel="noopener">Контактный лист</a><a class="sheet" target="_blank" rel="noopener">Спрайтшит</a><a class="provider" target="_blank" rel="noopener">До правки фаз</a></div>
      <div class="asset-links sources source-links"><a class="reference" target="_blank" rel="noopener">Референс пластины</a><a class="original" target="_blank" rel="noopener">Исходник кузнеца</a></div>`;
    card.querySelector("h3").textContent = title;
    const canvas = card.querySelector("canvas");
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    const counter = card.querySelector(".counter");
    const scrub = card.querySelector(".scrub");
    const playButton = card.querySelector(".toggle");
    const frameImages = Array.from({ length: 9 }, (_, frame) => {
      const image = new Image();
      image.src = asset(`${folder}/frame-${String(frame + 1).padStart(2, "0")}.png`);
      image.addEventListener("load", () => {
        card.querySelector(".missing").hidden = true;
        if (state.frame === frame) draw();
      });
      image.addEventListener("error", () => {
        if (frame === 0) card.querySelector(".missing").hidden = false;
      });
      return image;
    });
    const state = { frame: 0, playing: true };

    function draw() {
      const image = frameImages[state.frame];
      counter.value = `${String(state.frame + 1).padStart(2, "0")} / 09`;
      scrub.value = String(state.frame);
      const contact = index === 2 ? 3 : 4;
      const spark = contact + 1;
      card.querySelector(".phase").textContent = state.frame === contact ? "Контакт · без искр" : state.frame === spark ? "Искры · после удара" : state.frame < contact ? "Замах и подход" : "Возврат";
      if (!image.complete || image.naturalWidth === 0) return;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    }
    function setFrame(frame) {
      state.frame = (frame + frameImages.length) % frameImages.length;
      draw();
    }
    playButton.addEventListener("click", () => {
      state.playing = !state.playing;
      playButton.textContent = state.playing ? "Пауза" : "Играть";
    });
    function manualFrame(frame) {
      state.playing = false;
      playButton.textContent = "Играть";
      setFrame(frame);
    }
    card.querySelector(".prev").addEventListener("click", () => manualFrame(state.frame - 1));
    card.querySelector(".next").addEventListener("click", () => manualFrame(state.frame + 1));
    scrub.addEventListener("input", () => manualFrame(Number(scrub.value)));
    card.querySelector(".gif").href = asset(`${folder}/loop.gif`);
    card.querySelector(".contact").href = asset(`${folder}/contact.png`);
    card.querySelector(".sheet").href = asset(`${folder}/spritesheet.png`);
    card.querySelector(".provider").href = asset(`provider-animations/smith-${String(index + 1).padStart(2, "0")}/contact.png`);
    card.querySelector(".reference").href = asset("plate-reference.png");
    card.querySelector(".original").href = asset("sources/smith-user.png");
    cards.push({ state, setFrame });
    return card;
  }

  const container = document.querySelector(".variants");
  TITLES.forEach((title, index) => container.append(makeCard(index, title)));
  document.querySelectorAll("[data-preview]").forEach((image) => {
    image.addEventListener("error", () => {
      image.hidden = true;
      image.parentElement.querySelector(".preview-note").hidden = false;
    });
  });

  document.querySelector("[data-all]").addEventListener("click", (event) => {
    globalPlaying = !globalPlaying;
    cards.forEach(({ state }) => { state.playing = globalPlaying; });
    document.querySelectorAll(".variant .toggle").forEach((button) => { button.textContent = globalPlaying ? "Пауза" : "Играть"; });
    event.currentTarget.textContent = globalPlaying ? "Пауза всех" : "Играть все";
  });
  document.querySelector("[data-bg]").addEventListener("change", (event) => {
    document.querySelectorAll(".stage").forEach((stage) => {
      stage.classList.remove("checker", "dark", "grass");
      stage.classList.add(event.currentTarget.value);
    });
  });
  document.querySelector("[data-pixel]").addEventListener("change", (event) => {
    document.body.classList.toggle("smooth", !event.currentTarget.checked);
  });

  function tick(time) {
    if (time - lastTick >= frameMilliseconds) {
      lastTick = time;
      cards.forEach(({ state, setFrame }) => {
        if (state.playing) setFrame(state.frame + 1);
      });
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
