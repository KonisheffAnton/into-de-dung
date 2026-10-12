# Передача — 2026-10-12: исправлено лицо idle разбойника
D:\Games\into-de-dung; main; base23f08e1d7efb98967090299db08bc872e120de30.
U поручил рисунок/idle разбойника; анимации только PixelLab.
Статичная imagegen-правка и исходник — docs/art/rogue-idle-20261012/README.md.
Первую idle-пробу U отклонил: лицо скачет. Она сохранена; прежнее техническое
APPROVE не означает художественную приёмку. Диагностика нашла сдвиг и смену черт.
Новая цельная проба PixelLab закрепляет голову и двигает плечи/руки на1px.
Пакет: docs/art/rogue-idle-face-stable-20261012/README.md; preview.gif,
idle-native.gif, face-filmstrip.png, head-filmstrip.png и запросы/ответ рядом.
Отчёт: test_reports/rogue-idle-face-stable-20261012/REPORT.md.
Контрольная область лица11×11 одинакова во всех12 PNG (один хеш вместо7);
глаз/нос/подбородок не меняются. Голова/кинжалы просмотрены на ленте.
PNG128×128, alpha0/255, рамка16px, GIF12×200ms, Node PASS; ревью APPROVE.
Край капюшона слегка меняется.
Новая петля2.4s, все кадры PixelLab без дорисовки/интерполяции.
Новый job completed, usage3generations. Отказ edit-animation — в пакете.
Следующий шаг — отзыв U о новой петле. Статика/анимация ещё не утверждены;
интеграция/игровая посадка не выполнены. Новые действия без поручения не начинать.
Варианты одежды — в конце утверждённого персонажа; ART_DIRECTION владеет правилом.
Godot/full/core/F5/editor/GPU не запускались; игровые ассеты/runtime прежние.
Защитник: гаммы/переходы приняты; BATTLE_VISUAL_SCENE_CONTRACT — lifecycle.
Опубликованный арт — codex/approved-defender-art-20261012,64ba319d; HISTORY.
Игровая интеграция/гаммы локальны; «Ветеран» не подключён. Push нет.
Незакоммиченное: пользовательская scenes/demo/main_menu.tscn;
не трогать/сбрасывать/коммитить. Без поручения ничего не push.
PROJECT_CONTEXT — маршруты; CODEX_WORKFLOW — процесс; DESIGN_DIRECTION §7 — порядок.
Сохранять preview/live/worker/queue/RNG/save/frozen; инициативы нет, BT/адаптер прежние.
Старые save не менять/мигрировать/удалять; capture/restore default, clone эксперимент.
P-удар/тени/свет/баланс/backlog не начинать. PixelLab — GRAPHICS_WORKFLOW;
DPAPI только api.pixellab.ai, вне Git/логов. Без sidebar/расписаний.
После этапа Conventional Commit; короткий HANDOFF, прежний побайтно архивом+HISTORY.
В конце/при блокере предложить новый чат и дать полный промпт прямо в финале:
HEAD/результат/docs/artifacts/остаток/ограничения/проверки и это же правило передачи.
Ссылка не заменяет текст; следующий срез/чат автоматически не запускать.
