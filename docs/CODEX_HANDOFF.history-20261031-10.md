# Передача — 2026-10-31: задержки вывода кадров

D:/Games/into-de-dung; main; base 68cb84416d3a6b05ac0edee32e299287256615f6.
Цель стабильных 60 FPS с 24+ персонажами НЕ достигнута.
[Диагностика/следующий шаг](performance/battle-frame-pacing-20261031.md),
[прежние оптимизации и бой 32 фигур](performance/battle-soak-20261031.md).
Игровой runtime не менялся; performance tests теперь сохраняют экран/Hz/окно/GPU
до/после замера. Core/preview/queue/RNG/save/frozen сохранены.

44 длинных display-интервала боя возникли после готовности кадров:
GPU завершал их до показа предыдущего. Пики покоя совпали с DxgKrnl VSyncDPC;
это не независимый датчик экрана. Физический scanout и виновник не установлены.
Контроль queue2/images2 не помог: display max59.190 мс,4/3556 >20 мс.
Запрос queue1 фактически дал RD delay2 и исключён; override удалён.
Настройки ОС/VSync не менялись.

WPR CPU/GPU отказал0xc5585011: нет Profile system performance.
Системного ETL нет, сбор не запущен.
User-level ETW доступен и записан; нужны CPU scheduling/ISR/DPC/стеки.
Ожидается внешний сбор из терминала администратора:
python test_reports/battle-frame-pacing-20261031/capture_system_trace.py
Helper проверен, настройки не меняет, сам права не повышает. Elevated-путь не запускался.
Далее: разобрать полученный ETL, подтверждённое исправление, повторный длительный бой.

PASS: Godot import/parse, headless/GPU metadata probes; независимое APPROVE.
Диагностика APPROVE_WITH_LIMITATIONS; helper parse/nonadmin/mock cleanup PASS+APPROVE.
Артефакты: test_reports/battle-frame-pacing-20261031/; validation.json, review.md,
event-correlation.json, raw ETL/CSV и helper.
Прежние проверки и baseline FAIL — в отчёте боя; не повторялись.
Full/F5/движение/zoom/DPI/другой GPU, HUD/lifecycle/цвета/Колода/упор открыты.
Галерея/арт отдельно: docs/art/warrior-animation-six-20261031/README.md; приёмка открыта.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены33/33 SHA; не reset/stage/commit. Своих незакоммиченных после commit нет.
Без push/sidebar tasks/расписаний, нового арта/генерации/интеграции.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261031-9.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
