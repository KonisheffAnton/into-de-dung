(() => {
  "use strict";

  function setView(section, mode) {
    const image = section.querySelector("[data-image]");
    const note = section.querySelector(".image-note");
    const label = section.querySelector("[data-label]");
    const source = mode === "source";
    image.hidden = false;
    note.hidden = true;
    image.classList.toggle("original", source);
    image.alt = `${section.dataset.scene === "bright" ? "Яркая" : "Приглушённая"} диорама: ${source ? "эталон" : "16-битная версия"}`;
    section.querySelectorAll("[data-mode]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.mode === mode));
    });
    label.textContent = source ? "Загрузка эталона…" : "Загрузка 16-битной версии…";
    image.onload = () => {
      image.hidden = false;
      note.hidden = true;
      label.textContent = `${source ? "Эталон" : "16-битная версия"} · ${image.naturalWidth}×${image.naturalHeight}`;
      applyScale(section);
    };
    image.onerror = () => {
      if (!source) {
        image.hidden = true;
        note.hidden = false;
      }
    };
    image.src = source ? section.dataset.source : section.dataset.output;
    section.dataset.mode = mode;
  }

  function applyScale(section) {
    const image = section.querySelector("[data-image]");
    const scale = section.dataset.scale || "fit";
    image.style.maxWidth = scale === "fit" ? "100%" : "none";
    image.style.maxHeight = scale === "fit" ? "72vh" : "none";
    image.style.width = scale === "fit" ? "auto" : `${image.naturalWidth * Number(scale)}px`;
    image.style.height = "auto";
    section.querySelectorAll("[data-scale]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.scale === scale));
    });
  }

  document.querySelectorAll(".diorama").forEach((section) => {
    section.dataset.scale = "fit";
    section.querySelectorAll("[data-mode]").forEach((button) => {
      button.addEventListener("click", () => setView(section, button.dataset.mode));
    });
    section.querySelectorAll("[data-scale]").forEach((button) => {
      button.addEventListener("click", () => {
        section.dataset.scale = button.dataset.scale;
        applyScale(section);
      });
    });
    const fullscreenButton = section.querySelector("[data-fullscreen]");
    fullscreenButton.addEventListener("click", async () => {
      const viewer = section.querySelector(".viewer");
      try {
        if (document.fullscreenElement === viewer) {
          await document.exitFullscreen();
        } else if (viewer.requestFullscreen) {
          await viewer.requestFullscreen();
        }
      } catch {
        section.querySelector("[data-label]").textContent = "Полный экран недоступен; изображение можно открыть отдельно.";
      }
    });
    document.addEventListener("fullscreenchange", () => {
      fullscreenButton.textContent = document.fullscreenElement === section.querySelector(".viewer")
        ? "Выйти из полного экрана" : "На весь экран";
    });
    setView(section, "output");
  });
})();
