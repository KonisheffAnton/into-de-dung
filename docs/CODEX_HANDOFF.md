# Передача — 2026-10-14: характеристики, только документация
D:\Games\into-de-dung; main; base130e21578ec566ce3a703a4b9c4b838359942390.
U согласовал характеристики/формулы и поручил их записать; код не начинать.
Единый владелец решений и открытых вопросов — [CHARACTER_ATTRIBUTES_V1](CHARACTER_ATTRIBUTES_V1.md).
DESIGN_DIRECTION/маршруты обновлены; текущие контракты отделены от будущего дизайна.
Открыты точность/хранение дробей, момент считывания атрибутов автора тика,
алгоритм найма/темп XP, полный порядок прочих модификаторов и возможный размер карты.
Проверки документации и ревью: test_reports/character-attributes-design-20261014/REPORT.md.
Godot/full/core/F5/editor/DPI/GPU не запускались; игровой баланс не проверен.
Прежний HANDOFF сохранён побайтно отдельно; ссылка и итог этапа — [HISTORY](HISTORY.md).
Рестарт уровня кнопкой/R уже реализован; плейтест пользователя открыт.
Контракт: [боевой HUD](BATTLE_HUD_SCENES_V1.md#рестарт-текущего-уровня);
прежние PASS import/startup/render и ревью: test_reports/level-restart-20261014/REPORT.md.
Окружение: [SURROUND_DAMAGE](SURROUND_DAMAGE.md); жалоба 9/8 снята без правок урона.
Прежние свидетельства: test_reports/surround-damage-20261014/REPORT.md
и damage-comparison-investigation.md там же; частная причина 9/8 не установлена.
Лучница idle подключена, U «пока ок, но потом поправим цвет».
Арт: assets/art_presets/trials/archer_idle_v1/README.md,
docs/art/archer-perspective-20261014/README.md; прежние A–F/B сохранены.
Rogue: гаммы/темп/fade/зернистость/B1/швы открыты; Защитник принят,
Ветеран не подключён. Новые генерации/цвета/клипы только по поручению U.
Анимации только PixelLab, пробы сохранять; позы/alpha вручную не менять,
исключение — RGB Rogue B1. DPAPI вне Git/логов, только api.pixellab.ai.
scenes/demo/main_menu.tscn — пользовательский dirty: не трогать/reset/stage/commit.
Сохранять core/preview/live/worker/queue/RNG/save/frozen; без push/sidebar/расписаний,
P-удара/теней/света/дальнейшего баланса. Ждать U, реализацию/новый этап не начинать.
После этапа Conventional Commit, короткий HANDOFF; прежний побайтно отдельным
архивом+HISTORY. В финале/при блокере предложить новый чат и полный промпт:
HEAD/результат/docs/artifacts/остаток/ограничения/проверки и это же правило передачи.
Чат автоматически не создавать; ссылка не заменяет текст промпта.
