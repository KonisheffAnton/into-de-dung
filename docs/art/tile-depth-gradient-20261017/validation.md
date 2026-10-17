# Проверки этапа — 2026-10-17

Base main `2b488ce1bb2a8cf5d35d66a295a486d53d663650`.
Три поручения U: посадка Лучницы, текущий яркий эталон Защитника, объём тайлов
с градиентом боковин. Godot4.7.2/OpenGL Compatibility/RTX3050 Laptop.

Первый целевой прогон Archer: `--render-check --only archer_idle archer_cloth_palette unit_visual_contract`
в `test_reports/demo-2bd0c2b94dcc4aae89f8e6fffb871df4/`:4PASS/1FAIL.
Два новых ожидания в Archer сравнивали root с состоянием до штатного resize.
Baseline fixture исправлен перед переходами; runtime не менялся.

Свежий объединённый `--render-check --only current_art_zoom art_trial_battle demo presentation_foundation`
в `test_reports/demo-2775f516b2ff4a5fb779a9b50a18a026/`:24PASS/1FAIL/0timeout.
PASS: import/startup, Archer68/0, cloth206/0, zoom460/0, unit33/0, анимации,
гаммы/смерти, visual lifecycle, foundation, consequences/environment, камера,
demo и execution UI. Единственный отказ — type inference новой переменной
depth_ok в test_art_trial_battle, тест не загрузился. Явные типы исправлены;
runtime прежний. После копирования только исправленного теста в импортированную
изолированную копию адресный повтор **art_trial_battle446/0**.
Первый manifest сохраняет первоначальный snapshot; повтор — диагностический,
не новый чистый полный gate. Лог: `test_reports/tile-depth-gradient-20261017/art-trial-fixed.log`.

Render-аудиты:
- [Лучница](../archer-placement-20261017/render_audit.gd):74/0; все12 кадров обеих
  сторон, неизменные shadow/root, весь силуэт внутри прежних bounds пикинга.
- [Тайлы](render_audit.gd):17/0; floor0, elevated+, negative, wall, void;
  верхние вершины/пикинг/root и пиксели чистого authored верха сохранены.
  Первый16/1 сравнивал negative-top со старой перевёрнутой боковиной, которая
  перекрывала часть поверхности. Baseline уточнён до authored верха без боковин;
  новая геометрия ниже него. Это не маскировка изменения PNG/UV.
- [Эталон](../defender-current-reference-20261017/render-validation.json):PASS,
  alpha0 изменений, RGB38876; текущий PlayerWarriorSprite/material, без генерации.

Ведущий просмотрел сравнения и реальное поле1600×1200. Независимое ревью
фиксированного diff и снимков: **APPROVE**, game_reviewer gpt-6-sol/high,
только чтение. Ошибка разбора теста P1 закрыта повтором446/0.
Дополнительное критическое архитектурное ревью не требуется; ведущий проверил
границы: core/preview/live/worker/queue/RNG/save/frozen прежние.
Полный gate после fixture-правки не повторяли. Full/core, ручные F5/editor/DPI/GPU,
финальная приёмка новой посадки и боковин не выполнены. Выбор статичного эталона
разрешён U и не является приёмкой всех анимаций или финального арта.

Проверки ведущего при завершении:157 исходных PNG assets сверены с base2b488ce1,
все побайтно прежние; новый эталон добавлен отдельно. Шесть финальных runtime/test
файлов совпадают с проверенной изолированной копией (тест art_trial обновлён
отдельно для исправленного адресного повтора). Ссылки/manifest/diff проверены.
main_menu.tscn SHA256 `A64C270256EBF2EA073081200BE23028F792F42C3CA98F83A6499C1300A68668`
сохранён, сцена и untracked серия03 исключены из коммитов. Без push.
Прежний HANDOFF history-20261017-13 побайтный, SHA256
`3d4b86ca0eb91c6c42b1d57ecbeb8871beae629b229a6b8535c07d8b1480c6ba`;
его Git blob совпадает с прежним HANDOFF. Закрытие трёх поручений общее,
логические изменения разделены по Conventional Commit.
Входные документы, символы LF (архив отдельно): AGENTS4565→4565,
PROJECT_CONTEXT3491→3491, CODEX_WORKFLOW4482→4482, HANDOFF2375→2477/34 строки.
Уникальные запреты, открытые вопросы и границы приёмки сохранены.
