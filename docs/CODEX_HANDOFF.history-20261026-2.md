# Передача — 2026-10-26: герои в стиле Kingdom Rush

D:\Games\into-de-dung; main; base 1a9bb842ffc1aa89da041e26ed9c64be0ef12771.
U поручил найти 2D-референсы, сделать 4 героев и то же задание передать PixelLab.
Позже приложил поле с воином, лучником, магом и разбойником как основу образов.
Готовы 4 ImageGen + 4 PixelLab, исходные прозрачные PNG без правки пикселей.
[Пакет/референсы/промпты/ограничения](art/kingdom-rush-characters-20261026/README.md),
[галерея](art/kingdom-rush-characters-20261026/gallery.html).
ImageGen ближе к гладкому 2D; PixelLab дал пиксельную интерпретацию.
Это предложение для выбора U, integration=false; warrior_format_v1 не заменён.
Сцены, runtime, механики и анимации не менялись.

Проверки: 8 PNG, alpha/видимые поля, общие промпты и исходные референсы PASS.
ImageGen совпадает с оригиналами; фактические PixelLab запросы получили те же
тексты и байты референсов. 4 jobs completed, по25 генераций, всего100; USD0.
Браузер: 8/8 изображений, снимки128/256, масштаб/фон/сглаживание PASS, JS errors0.
Независимый reviewer APPROVE для сохранения/передачи и финальных LF/SHA.
Пакетные SHA/валидация внутри пакета; raw API/ревью/closeout:
test_reports/kingdom-rush-characters-20261026/ (вне Git, без ключей/headers).
Godot/full/core/F5/editor/DPI/GPU, анимация и финальная арт-приёмка не заявлены.

Остаток: выбор U между сериями и отзыв о виде. Ничего не внедрять автоматически.
Прежние отзывы о Колоде и одиночном упоре остаются открыты;
правило упора — [K16](PUSH_CHAIN_K16.md), следующие механики — отдельный выбор.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
остаются dirty; 33 SHA сохранены. Не трогать/reset/stage/commit.
Сохранять preview/live/worker/queue/RNG/save/frozen; без push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261026.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило передачи. Чат автоматически не создавать.
