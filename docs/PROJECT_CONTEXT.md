# intoDeDung — карта контекста

Сначала [HANDOFF](CODEX_HANDOFF.md) и git status/HEAD, затем выбрать нужную строку.
[AGENTS](../AGENTS.md) задаёт правила; уже предоставленный актуальный текст не перечитывать.
Таблица — маршруты. Контракт/код/тесты
читать адресно; историю и ссылки следующего уровня — только для конкретного вопроса.

| Задача | Документ |
|---|---|
| Архитектура / инварианты | [ARCHITECTURE](ARCHITECTURE.md) / [DECISIONS](DECISIONS.md) |
| Готовность ядра / следующий срез | [CORE_READINESS](CORE_READINESS.md) / §7 [DESIGN_DIRECTION](DESIGN_DIRECTION.md) |
| Делегирование / ведение контекста | [CODEX_WORKFLOW](CODEX_WORKFLOW.md) |
| Запуск / автоматические проверки | [REPOSITORY_STATE](REPOSITORY_STATE.md) / [TESTING](TESTING.md) |
| Боевой пакет / расстановка / плейтест | [CORE_BATTLE_BATCH_K9](CORE_BATTLE_BATCH_K9.md) |
| Перки: скрытая атака, Оппортунист/Прикрытие | [CORE_REACTIONS_K10](CORE_REACTIONS_K10.md) |
| Контратака / общий заряд | [COUNTERATTACK_K12](COUNTERATTACK_K12.md) |
| Отход / цепной толчок | [K14](SAFE_RETREAT_K14.md) / [K16](PUSH_CHAIN_K16.md) |
| Обрушение / фаза среды | [ENVIRONMENT_COLLAPSE_K15](ENVIRONMENT_COLLAPSE_K15.md) |
| Оглушающий удар и иммунитеты контроля | [CONTROL_PACKAGE_K11](CONTROL_PACKAGE_K11.md) |
| Поток исполнения / владение runtime и вид UI | [BATTLE_EXECUTION_UI](BATTLE_EXECUTION_UI.md) |
| Бой, управление | [TACTICAL_BATTLE](TACTICAL_BATTLE.md) |
| Сравнение командных ходов и инициативы | [INITIATIVE_COMPARISON](INITIATIVE_COMPARISON.md) |
| Проход через союзников | [ALLY_TRANSIT](ALLY_TRANSIT.md) |
| Дизайн брони, формулы, пути урона | [ARMOR_DAMAGE_D0](ARMOR_DAMAGE_D0.md) |
| Выделенный расчёт атаки D1/M2a | [ATTACK_DAMAGE_D1](ATTACK_DAMAGE_D1.md) |
| Реализованная броня и типы D2 | [ARMOR_DAMAGE_D2](ARMOR_DAMAGE_D2.md) |
| Эффекты K17 / legacy D3 | [K17](STATUS_EFFECTS_NEXT.md) / [D3](BLEEDING_D3.md) |
| Подготовка, вещи, сохранение забега D4 | [EXPEDITION_D4](EXPEDITION_D4.md) |
| Шипы, тела, поднятие D5 | [ENVIRONMENT_D5](ENVIRONMENT_D5.md) |
| Шаблон помощника, снимки M1 | [SUMMON_DEFINITION_M1](SUMMON_DEFINITION_M1.md) |
| Крит, спина, оглушение/путы C1 | [CRITICAL_BACKSTAB_C1](CRITICAL_BACKSTAB_C1.md) |
| Наложение пут опутывающим ударом K8 | [ENTANGLE_ATTACK_K8](ENTANGLE_ATTACK_K8.md) |
| Прогноз / стойка | [ATTACK_FORECAST](ATTACK_FORECAST.md) / [ACTION_PANEL_GUARD](ACTION_PANEL_GUARD.md) |
| Флакон / призыв предметом | [HEALING_ITEM](HEALING_ITEM.md) / [SUMMON_ITEM](SUMMON_ITEM.md) |
| Предметы M3 | [ITEM_USE_M3](ITEM_USE_M3.md) |
| Пробивание физической базы оружием M4 | [ARMOR_PIERCING_M4](ARMOR_PIERCING_M4.md) |
| Исполнение, маршруты к frozen Pxx | [COMMAND_ACTION_QUEUE_CONTRACT](COMMAND_ACTION_QUEUE_CONTRACT.md) |
| Будущий дизайн / кандидаты модульности | [TACTICAL_DESIGN_NEXT](TACTICAL_DESIGN_NEXT.md) / [MODULARITY_PLAN](MODULARITY_PLAN.md) |
| Свидетельства прошлых этапов, архивы | [HISTORY](HISTORY.md) |

Последнее указание пользователя задаёт желаемое изменение, но не доказывает
реализацию. Факты сверять с кодом и контрактом; проверки имеют дату и commit.
При расхождении описать его до зависимой работы. План, принятое решение,
реализация, техническая проверка и пользовательская приёмка — разные статусы.
Frozen Pxx описывают свои этапы; последующие изменения — в контрактах механизмов.
Не переписывать frozen текст под новое поведение. *.history-*.md и docs/modules/
хранят историю; это не текущие инструкции. Наличие плана не разрешает его выполнение.
