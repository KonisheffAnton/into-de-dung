# intoDeDung — карта контекста

Сначала [HANDOFF](CODEX_HANDOFF.md) и git status/HEAD, затем выбрать нужную строку.
[AGENTS](../AGENTS.md) задаёт правила; уже предоставленный актуальный текст не перечитывать.
Таблица — маршруты по задаче, не список обязательного чтения. Контракт/код/тесты
читать адресно; историю и ссылки следующего уровня — только для конкретного вопроса.

| Задача | Документ |
|---|---|
| Владельцы поведения / архитектурные инварианты | [ARCHITECTURE](ARCHITECTURE.md) / [DECISIONS](DECISIONS.md) |
| Выбор следующего среза / концепция | §7 / нужный раздел [DESIGN_DIRECTION](DESIGN_DIRECTION.md) |
| Делегирование, ведение и проверка объёма контекста | [CODEX_WORKFLOW](CODEX_WORKFLOW.md) |
| Запуск / автоматические проверки | [REPOSITORY_STATE](REPOSITORY_STATE.md) / [TESTING](TESTING.md) |
| Нынешний бой, управление | [TACTICAL_BATTLE](TACTICAL_BATTLE.md) |
| Проход через союзников | [ALLY_TRANSIT](ALLY_TRANSIT.md) |
| Дизайн брони, формулы, пути урона | [ARMOR_DAMAGE_D0](ARMOR_DAMAGE_D0.md) |
| Выделенный расчёт атаки D1/M2a | [ATTACK_DAMAGE_D1](ATTACK_DAMAGE_D1.md) |
| Реализованная броня и типы D2 | [ARMOR_DAMAGE_D2](ARMOR_DAMAGE_D2.md) |
| Кровотечение D3 | [BLEEDING_D3](BLEEDING_D3.md) |
| Подготовка, вещи, сохранение забега D4 | [EXPEDITION_D4](EXPEDITION_D4.md) |
| Шипы, тела, поднятие D5 | [ENVIRONMENT_D5](ENVIRONMENT_D5.md) |
| Шаблон помощника, снимки M1 | [SUMMON_DEFINITION_M1](SUMMON_DEFINITION_M1.md) |
| Крит, спина, оглушение/путы C1 | [CRITICAL_BACKSTAB_C1](CRITICAL_BACKSTAB_C1.md) |
| Прогноз / стойка | [ATTACK_FORECAST](ATTACK_FORECAST.md) / [ACTION_PANEL_GUARD](ACTION_PANEL_GUARD.md) |
| Флакон / призыв предметом | [HEALING_ITEM](HEALING_ITEM.md) / [SUMMON_ITEM](SUMMON_ITEM.md) |
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
