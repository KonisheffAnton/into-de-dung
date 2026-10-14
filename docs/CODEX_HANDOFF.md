# Передача — 2026-10-14: рестарт текущего уровня
D:\Games\into-de-dung; main; base23d526fae4279cfe97d815ef32f82a8f18bef97f.
U: «Отбой сейчас ок» по жалобе 9/8; затем кнопка рестарта без перезапуска игры.
HeroHubBattleView: «Рестарт уровня» в верхней строке и R повторяют текущий бой
с расстановки из того же run. Состав/вещи/seed/стартовая рука прежние;
прогресс попытки сбрасывается, профиль/файл/serial/награды не меняются.
Worker/показ, terminal и ошибка/pending save блокируют запрос.
Владение/границы: [боевой HUD](BATTLE_HUD_SCENES_V1.md#рестарт-текущего-уровня).
Godot import/startup/render PASS: H1 UI36/0, U14 UI56/0, deck UI128/0,
HUD302/0, execution UI28/0. PNG кнопки просмотрен; независимое ревью APPROVE.
Отчёт/запуск/validation: test_reports/level-restart-20261014/REPORT.md.
Full/core и ручные F5/editor/DPI/GPU-матрица не запускались; плейтест кнопки открыт.
Окружение: [SURROUND_DAMAGE](SURROUND_DAMAGE.md); жалоба снята без правок механики.
Прежние проверки/расследование: test_reports/surround-damage-20261014/REPORT.md
и damage-comparison-investigation.md там же. Причина частного 9/8 не установлена.
Лучница idle подключена; U «пока ок, но потом поправим цвет».
Runtime: assets/art_presets/trials/archer_idle_v1/README.md;
источники: docs/art/archer-perspective-20261014/README.md; A–F/B сохранены.
Rogue: гаммы/темп/fade/зернистость/B1/швы открыты; Защитник принят,
Ветеран не подключён. Новые генерации/цвета/клипы только по поручению U.
Анимации только PixelLab, пробы сохранять; позы/alpha вручную не менять,
исключение — RGB Rogue B1. DPAPI вне Git/логов, только api.pixellab.ai.
scenes/demo/main_menu.tscn — пользовательский dirty: не трогать/reset/stage/commit.
Сохранять core/preview/live/worker/queue/RNG/save/frozen; без push/sidebar/расписаний,
P-удара/теней/света/дальнейшего баланса. Ждать U, следующий этап не начинать.
После этапа Conventional Commit, короткий HANDOFF; прежний побайтно отдельным
архивом+HISTORY. В финале/при блокере предложить новый чат и полный промпт:
HEAD/результат/docs/artifacts/остаток/ограничения/проверки и это же правило передачи.
Чат автоматически не создавать; ссылка не заменяет текст промпта.
