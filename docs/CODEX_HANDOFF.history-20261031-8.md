# Передача — 2026-10-31: длительный бой с 32 бойцами

D:/Games/into-de-dung; main; base ed41c4f4e2d09fd86c34deae52b23de6a6c51a46.
Mobile/D3D12; batching земли/поз, transient индекс среды, phase opt-in;
owned frames без второй копии, постепенный release, один layout чисел,
повторный marker сохраняет сигналы без повторного HUD. Core не менялся.
[Метрики/ограничения/воспроизведение](performance/battle-soak-20261031.md).
Контракты: BATTLE_EXECUTION_UI, BATTLE_PRESENTATION_V1, BATTLE_VISUAL_SCENE_CONTRACT.

Пять раундов: 91 команда/555 шагов/106 DOT, минимум 29 живых из 32.
Финальный uncapped-прогон (3 раунда): 31853 кадра, p99 12.212 мс,
max 18.079 мс, 0 кадров >20 мс; 10 интервалов >16.667 мс.
Строгие 60 FPS ещё НЕ подтверждены. Финальный VSync (5 раундов):
engine p99 20.644/max27.869 мс, main max14.965 мс; display p99 17.794/
max24.268 мс, 44/15356 интервалов >20 мс. Задержки render/present/wait остаются.
Далее — спокойный плейтест и системный trace CPU/GPU scheduling/present;
процесс без admin. Fullscreen/queue3/Mailbox/Vulkan не дали устойчивого решения.
Системные настройки/драйверы не менялись; VSync остаётся включён.

PASS: импорт/разбор,30 suites/19656 assertions (core9424), launcher30/30;
независимое APPROVE. Те же baseline FAIL на ed41c4f:
presentation_foundation131/1 picking, turn_forecast_ui26/3.
Артефакты: test_reports/battle-soak-20261031/validation.json, review.md,
final-runtime-manifest.json, long32-release-verified.*, long32-vsync-release-final.*.
Full/ручной F5/движение/zoom/DPI/другой GPU не заявлены.
Прежние HUD/lifecycle/цвета17/11/Колода/упор остаются отдельной приёмкой.

Галерея: docs/art/warrior-animation-six-20261031/README.md; HTML локальный/ignored.
Нового арта/генерации/расхода/интеграции нет; стыки36 idle/ability и арт-приёмка открыты.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены33/33 SHA; не reset/stage/commit. Без push/sidebar tasks/расписаний.
Core/preview/queue/RNG/save/frozen сохранены. Своих незакоммиченных после commit нет.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261031-7.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
