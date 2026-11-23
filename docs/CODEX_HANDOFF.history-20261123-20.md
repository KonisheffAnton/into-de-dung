# Передача — 2026-11-23: статусы и полосы

D:/Games/into-de-dung; main; база 6566f0550d27280460006329b3b7b1995506457a.
[UI](art/status-icons-vitals-order-20261123/README.md): значки18px в слотах20px;
только счётчики статусов Play Bold AA. HP/броня/урон прежние. Полосы над рельефом;
невыбранные маскируются границами моделей, selected снимает маску. Наведение атаки
не выбор. Локальный слой отклонён U из-за тайлов; исправлено и переснято.
[Проверки](art/status-icons-vitals-order-20261123/verification.json): isolated import/startup,
4 адресных suites и поле/state/RNG parity PASS; review APPROVE.
Foundation141/2: те же2 отказа на baseline6566f055. Full/core/F5/Editor/resize/DPI/
performance не выполнены;60FPS не заявлены. Маска — bounds, не просветы силуэта.
Ручная приёмка открыта; контракт — BATTLE_PRESENTATION_REWORK.

[Все20 костей](art/bones-field-comparison-20261123/README.md) показаны, commit124d0d81:
PL29–38 в1:1, G21–30 уменьшены NEAREST; выбор открыт, в runtime не внедрены.
Свежие тела U решил показывать последним кадром смерти; переход ещё не внедрён.
Следующий шаг — отзыв U по UI и выбор костей; новый срез автоматически не начинать.

Книга заклинаний6566f055 реализована, ручная приёмка открыта: HUB_SCENES_V1
и art/mage-spellbook-ui-20261123/. Школы/развитие/финальный арт — Q.
Дух/труп носителя — концепт2ea6374f, runtime ещё host_defeat; Q у DESIGN_DIRECTION.
Обводкаf9e041b0 без приёмки; карты81c968ba: прежний full не зелёный,
старые nested save не мигрируются.
Чужие scenes/demo/main_menu.tscn, docs/art/battlefield-reference-03-20261017/,
ART_DIRECTION и пробы кнопок не reset/stage/commit; проверить status/HEAD.
Сохранить core/preview/queue/RNG/save/frozen,5 классов, PLAYER вправо/ENEMY влево,
возврат после атаки, правило брони,2:1↔4:3. Инициативы нет; команда3/лимит Q;
каталоги1–3 не мигрировать; H2–H5 не начинать.
Один isolated runner; без root import/служб/драйверов/фокуса ОС/push/sidebar/расписаний.
D:/Games/trog-grounding-check-20261122 не удалять: cleanup отклонён.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261123-19.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit своего, короткая передача;
прежнюю побайтно отдельно + HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Новый чат автоматически не создавать.
