(() => {
  "use strict";

  // Названия повторяют план запросов, чтобы карточки оставались читаемыми без загрузки JSON через file://.
  const VARIANTS = {
      crowd: {
      label: "Толпа · 8 персонажей", source: "inputs/crowd-256.png", raw: "sources/crowd.png",
      items: ["Короткие реплики", "Оглянуться", "Обсуждение карты", "Тихий разговор", "Слушатели"]
    },
    smith: {
      label: "Кузнец", source: "inputs/smith-256.png", raw: "sources/smith.png",
      items: ["Один удар", "Два лёгких удара", "Размеренный удар", "Короткий рабочий ритм", "Проверка и удар"]
    },
    market: {
      label: "Торговец и покупатель", source: "inputs/market-256.png", raw: "sources/market.png",
      items: ["Открытая ладонь", "Перечисляет доводы", "Показывает товар", "Убеждает покупателя", "Весёлая история"]
    }
  };

  const NOTES = {
    crowd: ["Очень тихое движение.", "Небольшие повороты головы.", "Обсуждение карты почти не читается.", "Тихие жесты и повороты.", "Очень сдержанные кивки."],
    smith: ["PixelLab добавил яркое свечение и искры.", "Искры до края кадра; два удара неявны.", "Размеренный удар; добавлены свечение и огонь.", "Сильный тёплый блик; два удара неявны.", "Один удар с огнём у клещей."],
    market: ["Жест ладонью; покупатель почти неподвижен.", "Жесты заметнее, реакция покупателя сдержанная.", "Жест в сторону; покупатель почти неподвижен.", "Дуга руки продавца; реакция покупателя слабая.", "Открытая ладонь и лёгкий подъём плеч."]
  };
  const cards = [];
  const currentFrame = new Map();
  let playing = true;
  let rate = 6;
  let lastStep = 0;
  const asUrl = (path) => new URL(path, location.href).href;

  function makeCard(category, index, title) {
    const folder = `animations/${category}-${String(index + 1).padStart(2, "0")}`;
    const article = document.createElement("article");
    article.className = "variant-card";
    article.innerHTML = `
      <div class="card-heading"><div><span class="eyebrow">Проба ${String(index + 1).padStart(2, "0")}</span><h3></h3></div><button type="button" class="quiet source-toggle">Источник</button></div>
      <div class="animation-stage background-checker"><canvas width="256" height="256" aria-label="Анимационная проба"></canvas><img class="source-preview" alt="Исходный кадр" hidden><span class="missing" hidden>Файлы ещё не добавлены</span></div>
      <div class="frame-links"><a class="source-file" target="_blank" rel="noopener">PNG-источник ↗</a><a class="contact-link" target="_blank" rel="noopener">Контактный лист ↗</a><a class="sheet-link" target="_blank" rel="noopener">Спрайтшит ↗</a><a class="gif-link" target="_blank" rel="noopener">GIF ↗</a></div>
      <details><summary>Кадры PNG</summary><div class="rawframes"></div></details>`;
    article.querySelector("h3").textContent = title;
    if (NOTES[category][index]) {
      const note = document.createElement("p");
      note.className = "variant-note";
      note.textContent = NOTES[category][index];
      article.querySelector(".frame-links").before(note);
    }
    const canvas = article.querySelector("canvas");
    const context = canvas.getContext("2d");
    context.imageSmoothingEnabled = false;
    const frames = Array.from({ length: 9 }, (_, frame) => {
      const image = new Image();
      image.src = asUrl(`${folder}/frame-${String(frame + 1).padStart(2, "0")}.png`);
      image.addEventListener("load", () => {
        if (currentFrame.get(canvas) === frame) drawFrame(canvas, context, image);
        article.querySelector(".missing").hidden = true;
      });
      image.addEventListener("error", () => {
        if (frame === 0) article.querySelector(".missing").hidden = false;
      });
      return image;
    });
    currentFrame.set(canvas, 0);
    frames[0].addEventListener("load", () => drawFrame(canvas, context, frames[0]));
    article.querySelector(".source-preview").src = asUrl(VARIANTS[category].source);
    article.querySelector(".source-file").href = asUrl(VARIANTS[category].raw);
    article.querySelector(".source-toggle").addEventListener("click", (event) => {
      const source = article.querySelector(".source-preview");
      source.hidden = !source.hidden;
      canvas.hidden = !source.hidden;
      event.currentTarget.textContent = source.hidden ? "Источник" : "Анимация";
    });
    article.querySelector(".contact-link").href = asUrl(`${folder}/contact.png`);
    article.querySelector(".sheet-link").href = asUrl(`${folder}/spritesheet.png`);
    article.querySelector(".gif-link").href = asUrl(`${folder}/loop.gif`);
    const rawframes = article.querySelector(".rawframes");
    frames.forEach((_, frame) => {
      const link = document.createElement("a");
      link.href = asUrl(`${folder}/frame-${String(frame + 1).padStart(2, "0")}.png`);
      link.textContent = `Кадр ${frame + 1}`;
      link.target = "_blank";
      link.rel = "noopener";
      rawframes.append(link);
    });
    cards.push({ canvas, context, frames, stage: article.querySelector(".animation-stage") });
    return article;
  }

  function drawFrame(canvas, context, image) {
    if (!image.complete || image.naturalWidth === 0) return;
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
  }

  Object.entries(VARIANTS).forEach(([category, config]) => {
    const panel = document.querySelector(`[data-panel="${category}"]`);
    config.items.forEach((title, index) => panel.append(makeCard(category, index, title)));
  });

  document.querySelectorAll("[data-category]").forEach((tab) => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("[data-category]").forEach((other) => other.setAttribute("aria-selected", String(other === tab)));
      document.querySelectorAll("[data-panel]").forEach((panel) => { panel.hidden = panel.dataset.panel !== tab.dataset.category; });
    });
  });

  document.querySelector("[data-play-all]").addEventListener("click", (event) => {
    playing = !playing;
    event.currentTarget.textContent = playing ? "Пауза" : "Воспроизвести";
    event.currentTarget.setAttribute("aria-pressed", String(playing));
  });
  document.querySelector("[data-speed]").addEventListener("change", (event) => { rate = Number(event.currentTarget.value); });
  document.querySelectorAll("[data-background-select]").forEach((select) => {
    select.addEventListener("change", () => {
      document.querySelectorAll(".diorama-pair img, .animation-stage").forEach((image) => {
        image.classList.remove("background-checker", "background-dark", "background-grass");
        image.classList.add(`background-${select.value}`);
      });
      document.querySelectorAll("[data-background-select]").forEach((other) => { other.value = select.value; });
    });
  });
  document.querySelectorAll("[data-nearest]").forEach((check) => {
    check.addEventListener("change", () => {
      document.documentElement.classList.toggle("smooth-pixels", !check.checked);
      document.querySelectorAll("[data-nearest]").forEach((other) => { other.checked = check.checked; });
    });
  });
  document.querySelectorAll("[data-diorama-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      const pair = document.querySelector(`[data-diorama="${button.dataset.dioramaToggle}"]`);
      pair.classList.toggle("source-focus");
      button.textContent = pair.classList.contains("source-focus") ? "Показать сравнение" : "Показать источник";
    });
  });

  function animate(time) {
    if (playing && time - lastStep >= 1000 / rate) {
      lastStep = time;
      cards.forEach(({ canvas, context, frames }) => {
        const next = ((currentFrame.get(canvas) || 0) + 1) % frames.length;
        currentFrame.set(canvas, next);
        drawFrame(canvas, context, frames[next]);
      });
    }
    requestAnimationFrame(animate);
  }
  requestAnimationFrame(animate);
})();
