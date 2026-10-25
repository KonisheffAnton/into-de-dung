# Передача — 2026-10-25: одиночный упор без урона оружия

D:\Games\into-de-dung; main; base 5dd8ed0f9f55c3ed67c2d96d164d6aa7dd6fd64a.
U поручил убрать WEAPON_DAMAGE из урона одиночной цели о стену/высокий уступ.
В ARMOR_PROFILE база этого последствия теперь max(0, STRENGTH).
Прямой удар, цепь/её конечный упор, падение и legacy-профили сохранены.
Правила и границы — [K16](PUSH_CHAIN_K16.md#одиночный-упор--u-2026-10-25).
BalancePushRules фиксирует базу до оплаты; общая очередь исполняет её
в admission, preview и live с прежней защитой. Save/snapshot не расширены.

Проверки: import/startup и 8 адресных suites — 10 PASS, 0 FAIL, 0 timeout.
Команда и область — [TESTING](TESTING.md); новые случаи в test_push_chain.gd.
Стена/уступ, дроби, сопротивление, нулевая сила, прямой удар и конец цепи;
preview/live, forecast/execution workers и sealed guards прошли.
Независимый game_reviewer: APPROVE; ведущий проверил критические границы.
Логи: test_reports/demo-0d9a305bc8154785b75cb68dd89853b9/.
Отчёт/ревью/SHA: test_reports/solo-wall-damage-20261025/.
Full/core, render и ручные F5/editor/DPI/GPU/баланс не запускались.

Остаток: ручной отзыв о новом уроне и прежней Колоде.
Школы, улучшение/разборка, отделка — только отдельный выбор U; не начинать автоматически.
Хаб/арт и прежний [остаток Rogue](art/rogue-model-death3-20261023/README.md) сохранены.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
остаются dirty; SHA33 сохранены. Не трогать/reset/stage/commit.
Сохранять preview/live/worker/queue/RNG/save/frozen; без push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261025.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило передачи. Чат автоматически не создавать.
