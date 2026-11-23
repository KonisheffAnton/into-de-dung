# Передача — 2026-11-23: раздел «Маг» и огонёк от прокачки

D:/Games/into-de-dung; main; база c227a766674b930a59e9e7c70e19bdd58332484e.
По U принят [целевой раздел «Маг»](DESIGN_DIRECTION.md#mage-section-progression-flame-20261123):
вкладки «Развитие»/«Колода», настройка имени/облика в развитии; огонёк зависит
от прокачки, ручной контроль только для тестов. Владелец — DESIGN_DIRECTION§3.2.1.
HUB_DESIGN_PLAN обновлён; HOST_POSSESSION/HUB_SCENES/MAGE_DECK различают
текущую реализацию и будущий концепт. Runtime/controls/save/schema не менялись.
[Проверки](../test_reports/mage-section-progression-flame-concept-20261123/validation.json):
diff, ссылки, побайтный архив, размеры и защищённые файлы. Только документация.
Улучшения/школы/пороги → вид огня, дерево/цены/баланс, тестовый доступ/override,
компоновка/арт/приёмка — Q. Следующий шаг — отдельное U, реализацию не начинать.

Прежний c227a766 — [20 вариантов костей](art/bones-twenty-exploration-20261123/README.md):
выбор U открыт, поле/масштаб ещё не проверены. Свежий PL-F3 и выступ — в пакете.
Обводка огонька f9e041b0 — [пакет](art/host-flame-outline-20261123/README.md),
ручная приёмка открыта. Вселение/карты81c968ba — [отчёт](art/host-possession-runtime-20261123/README.md);
прежний full не зелёный. Старые nested save формы не мигрируются.
Godot/import/full/core/F5/Editor/DPI/performance этим этапом не запускались;
прежние gates не повторены,60FPS не заявлены. HUD/гибель/тело мага — концепты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit; сверять status/HEAD, прочие параллельные правки исключать.
Сохранить core/preview/queue/RNG/save/frozen,5 классов F5, PLAYER вправо/ENEMY влево,
возврат после атаки, правило брони, пробу2:1↔4:3. Инициативы нет; команда3,
будущий лимит Q; каталоги1–3 не мигрировать. H2–H5/прочие Q не начинать.
Один isolated runner; без root import/служб/драйверов/фокуса ОС/push/sidebar/расписаний.
D:/Games/trog-grounding-check-20261122 не удалять: cleanup ранее отклонён.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261123-10.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit только своего, короткий HANDOFF;
прежний побайтно отдельно + HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать.
