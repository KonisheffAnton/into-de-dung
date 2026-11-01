# Передача — 2026-11-01: магия/карты и бой32

D:/Games/into-de-dung; main; base 3e959837189e15157a7b379fcae9ad371edb4159.
Цель — убрать фризы; стабильные60 FPS НЕ достигнуты.
[Результат/измерения/остаток](performance/battle-magic-pacing-20261101.md).

Убран повторный полный snapshot на hover/готовом прогнозе магии и карт:
BattleForecastFreshness проверяет точный raw graph, неизвестное — прежний fallback.
Режим обновляется по стадиям; готовая панель мага разделяет проверку свежести
с прогнозом. Live admission/preview/core/queue/RNG/save/frozen сохранены.
Контракты: ATTACK_FORECAST, BATTLE_EXECUTION_UI, MAGE_DECK_V1.
Hover32: около87мс → медианы3,76/4,62мс; это обработчики, не FPS.

Изолированный import/parse PASS; witness69/0, freshness UI53/0, mode25/0,
prep33/0+61/0, mage37/0, deck121/0, presenter164/0, async13/0,
execution59/0, planner61/0, Python30/0. Независимое APPROVE.
Состав — отчёт и test_reports/battle-magic-pacing-20261101/
validation.json, review.md; runtime/mirror1040 файлов совпали.

Окончательный interactive-soak32-final-ca9e5675*:352,47с,5 раундов,86/0,
минимум29 живых,91 команда, DOT/огонь,16565 синтетических mouse-motion.
Input медиана1,842/max6,230мс. Interactive p99/max20,742/29,502мс;
combat20,358/50,222мс. Фокус потерян с раунда4;50мс кадр был ещё focused:
main11,287 + draw/wait38,860мс. Причина ожидания не установлена.
PresentMon — диагностика, без точного process↔present mapping.
Предыдущий f00d5cdd весь focused, но до последних правок; не final acceptance.

Далее: current interactive CPU/GPU ETL с метками, пики публикации UI,
обычный isolate/настоящая мышь. Пользователь просит продолжать без него;
не повторять запрос фокуса. Full/core/F5/ручные движение/zoom/DPI/другой GPU
не заявлены. Прежние HUD/lifecycle/цвета/Колода/арт-приёмка открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit;33 файла сохранены. Один Godot runner, isolated project;
без root import/автоповышения/изменения служб/драйверов/принудительного фокуса.
Без push/sidebar tasks/расписаний/нового арта/генерации/интеграции.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261101-3.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
