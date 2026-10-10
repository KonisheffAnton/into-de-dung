# intoDeDung — маршруты

Старт: [HANDOFF](CODEX_HANDOFF.md), Git; [правила](../AGENTS.md) повторно не читать.
Код/контракты/историю читать адресно.

| Задача | Документ |
|---|---|
| Архитектура / инварианты | [ARCHITECTURE](ARCHITECTURE.md) / [DECISIONS](DECISIONS.md) |
| Готовность ядра / срез | [CORE_READINESS](CORE_READINESS.md) / §7 [DESIGN_DIRECTION](DESIGN_DIRECTION.md) |
| Команда / контекст | [CODEX_WORKFLOW](CODEX_WORKFLOW.md) |
| Графика | [ART](ART_DIRECTION.md) / [Пресеты](../assets/art_presets/approved/README.md) / [API](GRAPHICS_WORKFLOW.md) |
| Запуск / автоматические проверки | [REPOSITORY_STATE](REPOSITORY_STATE.md) / [TESTING](TESTING.md) |
| Хаб / итоги / сцены | [H1](HERO_HUB_H1.md) / [Итоги](POST_BATTLE_V1.md) / [Сцены](HUB_SCENES_V1.md) |
| Боевой пакет / расстановка / плейтест | [CORE_BATTLE_BATCH_K9](CORE_BATTLE_BATCH_K9.md) |
| Перки / Щитоносец | [K10](CORE_REACTIONS_K10.md) / [V1](SHIELDBEARER_V1.md) |
| Контратака | [K12](COUNTERATTACK_K12.md) |
| Доп. действие и реакции | [Запас](REACTION_BONUS_ACTIONS.md) |
| Отход / цепной толчок | [K14](SAFE_RETREAT_K14.md) / [K16](PUSH_CHAIN_K16.md) |
| Обрушение / фаза среды | [ENVIRONMENT_COLLAPSE_K15](ENVIRONMENT_COLLAPSE_K15.md) |
| Оглушающий удар и иммунитеты контроля | [CONTROL_PACKAGE_K11](CONTROL_PACKAGE_K11.md) |
| Показ | [UI](BATTLE_EXECUTION_UI.md) [V1](BATTLE_PRESENTATION_V1.md) [Пакеты](BATTLE_PRESENTATION_REWORK.md) [HUD](BATTLE_HUD_SCENES_V1.md) |
| Бой, управление | [TACTICAL_BATTLE](TACTICAL_BATTLE.md) |
| Эксперимент инициативы | [INITIATIVE_COMPARISON](INITIATIVE_COMPARISON.md) |
| Проход через союзников | [ALLY_TRANSIT](ALLY_TRANSIT.md) |
| Дизайн брони, формулы, пути урона | [ARMOR_DAMAGE_D0](ARMOR_DAMAGE_D0.md) |
| Выделенный расчёт атаки D1/M2a | [ATTACK_DAMAGE_D1](ATTACK_DAMAGE_D1.md) |
| Реализованная броня и типы D2 | [ARMOR_DAMAGE_D2](ARMOR_DAMAGE_D2.md) |
| Эффекты K17 / legacy D3 | [K17](STATUS_EFFECTS_NEXT.md) / [D3](BLEEDING_D3.md) |
| Маг, откаты / щит, призыв | [K18](MAGE_COOLDOWNS_K18.md) / [R14](MAGE_SUPPORT_R14.md) |
| Колода мага, рука / награды / костёр | [MAGE_DECK_V1](MAGE_DECK_V1.md) |
| Полный цикл / legacy D4 | [U14](EXPEDITION_U14.md) / [D4](EXPEDITION_D4.md) |
| Среда | [D5](ENVIRONMENT_D5.md) / [Ловушки](ENVIRONMENT_HAZARDS_V1.md) |
| Помощник / снимки | [M1](SUMMON_DEFINITION_M1.md) / [Снимки](BATTLE_SNAPSHOT_CURRENT.md) |
| Крит, спина, оглушение/путы C1 | [CRITICAL_BACKSTAB_C1](CRITICAL_BACKSTAB_C1.md) |
| Наложение пут опутывающим ударом K8 | [ENTANGLE_ATTACK_K8](ENTANGLE_ATTACK_K8.md) |
| Прогноз / стойка | [ATTACK_FORECAST](ATTACK_FORECAST.md) / [ACTION_PANEL_GUARD](ACTION_PANEL_GUARD.md) |
| Флакон / призыв предметом | [HEALING_ITEM](HEALING_ITEM.md) / [SUMMON_ITEM](SUMMON_ITEM.md) |
| Предметы M3 | [ITEM_USE_M3](ITEM_USE_M3.md) |
| Пробивание физической базы M4 | [ARMOR_PIERCING_M4](ARMOR_PIERCING_M4.md) |
| Исполнение / frozen Pxx | [COMMAND_ACTION_QUEUE_CONTRACT](COMMAND_ACTION_QUEUE_CONTRACT.md) |
| Будущий дизайн / кандидаты модульности | [TACTICAL_DESIGN_NEXT](TACTICAL_DESIGN_NEXT.md) / [MODULARITY_PLAN](MODULARITY_PLAN.md) |
| История | [HISTORY](HISTORY.md) |

Факты сверять с кодом/контрактом; проверки имеют дату и commit.
Расхождение описать до зависимой работы.
План, решение, реализация, техническая проверка и приёмка — разные статусы.
Frozen Pxx не переписывать; новое поведение — в контрактах механизмов.
*.history-*.md и docs/modules/ — история, не текущие инструкции.
План не разрешает выполнение.
