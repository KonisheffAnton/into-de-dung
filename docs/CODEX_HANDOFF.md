# Передача — 2026-09-21: D2, первый бой с новой бронёй

Main; base `5f688c4f7354a79072311d3690440d3b48ace3ba`, вход чистый.
По отдельному «продолжай» реализован [D2](ARMOR_DAMAGE_D2.md).
Итоговый HEAD/status — в completion.json отчёта ниже; сверить перед работой.
Все изменения этапа входят в итоговый commit; незакоммиченного остатка D2 нет.
Прежняя передача сохранена точным [снимком](CODEX_HANDOFF.history-20260921-16.md), ссылка в HISTORY.

Новый armor_spatial_v1 и явная UnitState.armor: physical/fire, точные дроби,
две ветви защит, p до hit, один net HP, расход E → условный RNG commit → a_i → HP.
Сохранены checkpoints/fault-prefix; collision/fall — отдельные hit.
Unit/ItemSimulation v4 сохраняют остатки/identity/E/защиты; старые оболочки не принимают Unit v4.
Forecast исполняет реальную очередь, включая истечение E при конце боя.
Кнопка «Броня»/armor_battle.tscn открывает отдельный бой; 4 восстанавливает20 за1 main
с MoveRules admission. Восстановление по недостаче, избыток в бою — E;
repair пока только чистый план с оплатой W, без склада/хаба/экрана.
Призыв новой capability явно недоступен. Legacy-профили/flat+bypass/calculator
отказывают для неё; прежние сценарии и D1 traces сохранены.

## Проверки

Import/startup, адресные runner, --check --full и --render-check PASS.
Расчёт брони68/0, snapshot35/0, integration263/0, recovery26/0, armor UI16/0.
D1 helper23555/0, 57 baseline-сценариев/502 assertions; core9440/0,
demo143/0, battle267/0. Настоящие input/scroll в SubViewport; PNG осмотрены.
Core diagnostics точно совпали с D1: intentional occupied-cell error, 47 ObjectDB/18 resources.
Независимое ревью revised результата — APPROVE. Три замечания закрыты регрессиями:
смешение версий snapshot, допуск восстановления, последовательные падения и item-heal.
Отчёт ignored: `test_reports/armor-damage-d2-20260921/`: verification.json,
review-initial.md/review.md, lead-review.md, manifests, completion.json, next-chat-prompt.txt.
Full: `test_reports/demo-1e07a554c46a4f51b71417ce07ec7815/`;
render: `test_reports/demo-ff573d7aa2824de99220682c9209f36c/`.

## Остаток и ограничения

D0 U/A/§9 приняты, Q1–Q6 не переоткрывать. D1/M2a и первый D2 завершены.
Следующий шаг — плейтест брони, затем отдельное поручение D3 на одно состояние.
D3–D5/M1/M2b/M3–M4 не запущены; прочие P вне брони не приняты. Графика отложена.
Технические детали решать самостоятельно; вопросы только при противоречиях с U, пакетом.
Точные API/числовые границы и неохваченные системы — D2; маршруты — PROJECT_CONTEXT.
Без push, sidebar tasks и расписаний. Frozen P02–P08/§4.5 не менять.
AGENTS/CODEX_WORKFLOW: ограниченное делегирование, контроль ведущим queue/snapshot/preview/RNG,
import/startup/адресные тесты → full/render → независимое ревью → логический commit.
Архивы *.history-*.md и docs/modules/ автоматически не читать.
В конце этапа/при блокере обновить короткий HANDOFF, сохранив прежний отдельным архивом
со ссылкой из HISTORY. Полный самодостаточный промпт следующего чата вывести прямо
в финальном сообщении блоком кода: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Ссылка не заменяет текст.
