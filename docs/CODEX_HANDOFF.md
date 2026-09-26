# Передача — 2026-09-26: стоимость исполнения боя

Ветка main; base `a22ae10cca13974f4ada1eb80dd89f45a80af05e`, чистый старт.
Прежняя передача — точный [архив](CODEX_HANDOFF.history-20260926-5.md).
Цель — плавный общий бой, крупные пакеты и один плейтест.
Новый чат — при необходимости; без новых механик.

Сокращены копии/повторная проверка локального board DTO внутри capture;
raw/from_dict/instantiate остаются строгими, кэша по revision нет.
Призыв/поднятие строят checkpoint через SummonMutationProjection без второго
runtime боя; полные post-state/admission/RNG/counters/identity guards сохранены.
Preview остаётся настоящим исполнением в изоляции. Владельцы: SUMMON_ITEM,
ENVIRONMENT_D5, ARCHITECTURE; прежние worker/hints — ATTACK_FORECAST/ITEM_USE_M3.

A/B с рендером, 8 окон на версию: медианный пик кадра движения 77 → 61 мс,
удара 110 → 88, конца хода 74 → 56, призыва ИИ 161 → 102. Итоговые
fingerprint/RNG/counters равны. Это один сценарий, не FPS/гарантия.
Полная плавность НЕ достигнута/не принята: live очередь синхронна.
Следующий крупный пакет — отделение отрисовки от исполнения. UI читает живые
UnitState, callbacks синхронны: перенос session в поток без владения небезопасен.

Godot 4.7.2: import/startup/full PASS, 69 headless записей, core 9440/0;
новые copy/capture/checkpoint 12/0,30/0,70/0. Девять связанных render runner PASS,
два PNG осмотрены; baseline diagnostics совпали, новых нет, manifests совпали.
Независимое APPROVE и ревью ведущего. Отчёт/validation/benchmark-final:
`test_reports/live-smoothness-20260926/report.md`; полный snapshot:
`test_reports/demo-421406f2de014b5d8cbc4d9f5e3d0ff4/project`.
SHA/status — completion и финал. Без push/sidebar tasks/расписаний.

K5–K7 приняты; K3 «Пока ок»; общий C1/K8–K11 открыт, D3/D4/D5 частичны.
Остаток CORE_READINESS, маршруты PROJECT_CONTEXT, выбор DESIGN_DIRECTION §7;
весь backlog не запускать. U14 согласована, карта не реализована; D4 линейный.
Ядро → хаб/мета → карта; баланс позже. Сохранять командный бой, D5/M1/M3,
1 main, остатки/RNG/ID, preview/live/FAULTED, формулы/цены/Q1–Q6/frozen.
Падение/инициатива отложены; P не равны согласованным правилам.

В конце этапа/при блокере обновить HANDOFF; прежний сохранить точно отдельным
архивом со ссылкой из HISTORY по CODEX_WORKFLOW. Предложить новый чат при
необходимости; прямо в финале дать полный самодостаточный промпт: HEAD,
результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Ссылка не заменяет текст; правило переносить дальше.
