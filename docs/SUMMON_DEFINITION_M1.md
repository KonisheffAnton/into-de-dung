# M1 — определение помощника

Пакет ведущего 2026-09-22, base `12e996f74c73a127ebd54d8ae1a0772a85923639`.
Контракт зафиксирован до реализации; M1 реализован, результаты проверки — HANDOFF.

`SummonDefinition extends Resource` хранит десять базовых float-параметров:
hp_max=16, armor=0, strength=4, weapon_damage=2, impact_power=3,
balance_max=5, move_range=4, main_actions_max=1, bonus_actions_max=1,
attack_range=1; name_prefix="Помощник · ", append_owner_name=true.
Нет ID, faction, cell, владельца, pending, текущих ресурсов или capability брони.
Только точный класс, конечные числа 0..4096; hp_max/balance_max >0,
attack_range >=1; main/bonus — целые. Prefix непустой, до 256 UTF-8 bytes;
итоговое имя до 4096 bytes проверяется до создания UnitState и оплаты.
Новые ограничения относятся к определениям, а не к историческим Unit stats.

`ItemDef.summon_definition` допускается только при use_summon.
Null у legacy печати означает новый экземпляр неизменного исходного шаблона,
не поиск в каталоге. Неверное ненулевое определение не заменяется default.
Создание печати в ItemOwnerState фиксирует проверенную глубокую копию;
повтор того же ID использует уже зафиксированную версию только при равных данных.
Getters печати возвращают копии. Повтор ID также требует совпадения имени и
описания самого предмета. Остальные предметы сохраняют прежний контракт.
Каждый helper имеет отдельные StatsBag/Vitals/ActionResources.
make_helper принимает необязательное определение; D5 использует default,
а capability D2/D3 по-прежнему добавляет RaiseCorpseCommand. Обычный исходный
погибший D5 не становится зарегистрированным summon из-за общей фабрики.

Writer сохраняет прежний минимальный envelope v1–v5 для default, включая
явный default Resource. Для нестандартного определения (даже неиспользованной
печати) пишет v6 `board_items_summon_definitions_v6`: payload v4 с summons,
armor-полями предметов и `summon_definition` в каждом descriptor.
У печати это полный DTO с schema_version=1 и всеми 12 полями; у других — {}.
Environment добавляется только при включённой среде и имеет прежнюю форму D5.
Наличие armor-полей v6 не включает armor capability у Unit или старой печати.
Board/Unit codecs не меняются. Старые формы сохраняют canonical bytes.

Raw preflight проверяет точные ключи/типы/границы/версию определения до allocation
доски, владельцев, предметов, runtime эффектов и помощников. Catalogue обязан
совпадать по всем влияющим значениям. Для v1–v5 legacy summon дополнительно
сравнивается с default; нестандартный внешний каталог отклоняется. Для v6
сравнивается полный DTO; несовпадение/отсутствие — отказ. После полной проверки
restore изолирует определения от каталога, не вызывает equip/refill.
Preview и callback preflight используют тот же codec и зафиксированные данные.

Не меняются цена, заряды, геометрия, ID/RNG, admission/pending/refill, BT,
FAULTED prefix, смерть/cleanup/исход, правила D5 и профиль D4. Помощник из
трупа не оставляет тела. Новый предмет, M2b/M3–M4 не входят в этап.

Приёмка: default/вариант через настоящую команду; исходный Resource/getter,
два владельца и повтор после смерти; invalid/stale без мутации; raw malformed
и версии; legacy bytes; roundtrip pending/ready без refill; forecast/live
включая lethal и неиспользованную печать; callback guard, RNG/counters; D5.
Import/startup, адресные тесты, full/render, PNG/input/scroll, затем независимое
ревью фиксированного результата и логический commit по CODEX_WORKFLOW.
