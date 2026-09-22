# Передача — 2026-09-22: D5 перепроверен, следующим выбран M1

Main; base `2fb3bcef92286807128f3427badc2bae92e39e2a`, вход чистый.
Итоговый SHA/status — `test_reports/d5-recheck-20260922/completion.json`; сверить Git.
Прежняя передача — точный [снимок](CODEX_HANDOFF.history-20260922-5.md), ссылка в HISTORY;
равенство рабочих байтов и Git blob проверено. После фиксации остатка нет.

Пользователь отложил ручную приёмку D5, поручил самостоятельную перепроверку
и выбрал следующим M1 — определение помощника. M1 ещё не реализован.
Уточнение: поднятый из тела помощник при смерти тела не оставляет.
Игровой код уже соблюдал это правило; добавлены регрессии смерти помощника от
входа в огонь после refill и от кровотечения. Проверены один died, отсутствие
corpse_created/тела, processed_deaths, свободная occupancy, повтор без мутаций
и decode/instantiate/recapture после смерти. Убийство атакой было покрыто ранее.

Import/startup/full/render PASS. D5 state23/0, integration168/0, UI23/0 и render29/0;
core9440/0, только прежние occupied-cell/47 ObjectDB/18 resources diagnostics.
Full: `test_reports/demo-55c5315d835448c4a5ce3089210ff63f/`.
Render: `test_reports/demo-0fcb4fb1d5774e6e8307300130dbbce7/`.
Шесть PNG/input/scroll проверены; финальные PNG равны уже осмотренным побайтно.
Код/тесты совпадают с manifest обоих прогонов; игровой код не менялся. Ревью APPROVE.
Дополнительные session партии — 89/0: победа за 5 раундов и поражение за 4;
в обеих поднятый помощник погиб без тела, terminal/reset/armor cleanup корректны.
Отчёты, review, probe, manifest, next-stage-scope и next-chat-prompt:
`test_reports/d5-recheck-20260922/`. Ручная приёмка D5 открыта, сейчас отложена.

Следующий шаг в новом чате: реализовать выбранный M1 по §M1 [MODULARITY_PLAN](MODULARITY_PLAN.md),
адаптировав пакет к нынешнему коду и снимкам v1–v5; выбор — §7 [DESIGN_DIRECTION](DESIGN_DIRECTION.md).
Вынести базовые stats/имя в типизированное Resource-определение, сохранить default
HP16/armor0/strength4/weapon2/impact3/balance5/move4/main1/bonus1/range1.
UseSummoningItemCommand.make_helper вызывают также RaiseCorpseCommand и D5 fixture;
сохранить различие обычного тела и зарегистрированного summon. Новый помощник
не оставляет тела. Определение изолируется при сборке боя, snapshot переносит
все влияющие значения; legacy canonical bytes, preview/live и callback guards сохранить.
До кодера зафиксировать validation/copy/writer/version/catalogue; runtime не хранить в Resource.
Не расширять capability старой печати на armor и не менять профиль D4 в рамках M1.

D5 — отдельный сценарий F5 → «Среда / трупы»; [контракт](ENVIRONMENT_D5.md) без изменений механики.
D2 принят; D3 частично; D4 подтверждён перенос экипировки, полная приёмка открыта.
Командные ходы/1 main за атаку сохранить; Q1–Q6/frozen P02–P08/§4.5 не менять.
Расширения D5, M2b/M3–M4, графику/метакомнату/экономику без поручения не запускать.
Без push/sidebar tasks/расписаний. AGENTS/CODEX_WORKFLOW: один пишущий кодер,
критические контракты у ведущего; import/startup, адресные/full/render, PNG/input,
независимое ревью фиксированного результата, логический commit и чистое дерево.
В конце этапа/при блокере обновить короткий HANDOFF, прежний сохранить точным
отдельным архивом со ссылкой из HISTORY. Для нового этапа предложить новый чат;
вывести полный самодостаточный промпт прямо в финале блоком кода: HEAD, результат,
docs/artifacts, остаток, ограничения, проверки и это же правило. Ссылка не заменяет текст.
