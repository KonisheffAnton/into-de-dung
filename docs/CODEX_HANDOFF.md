# Передача — 2026-10-23: новая модель разбойника и Смерть3
D:\Games\into-de-dung; main; base719fc6af81689ccf0bd4927a3f90350119e95bd4.
U поручил заменить модель разбойника и реализовать Смерть3 последней серии.
Обе фракции используют rogue_selected_v1:18 исходных PNG128² без правки,
первый кадр равен still; ArtRoot0.8, своя опора(64,83), enemy зеркалит рисунок.
Death17×150мс=2.55с +прежниеhold0.25/fade0.80=3.60с, затем штатное after/тело.
Idle не выбран: статичная поза; прежняя B1 отключена, guard общий.
Старые маски одежды не применяются, индекс выбора сохраняется.
[Контракт](BATTLE_VISUAL_SCENE_CONTRACT.md#анимации-разбойника),
[пакет/рендеры/проверки](art/rogue-model-death3-20261023/README.md).
[Внешние3idle/3смерти](art/rogue-selected-pixellab-20261023/README.md) сохранены.
25 итоговых PASS — агрегат: первый gate24/1/0, correctedguard31/0 иdefender299/0;
919 runtime/scene/asset SHA совпали. Import/startup, Rogue98/0, routes832/0,
cloth148/0, zoom500/0; render333/0 после исправления fixture. Reviewer APPROVE.
Первые сбои/timeout renderfixture сохранены; runtime при исправлении не менялся.
Full/core и ручные F5/editor/DPI/GPU/художественная приёмка не заявлены.
Ручная оценка масштаба/посадки/переходов открыта; падение вперёд-вправо.
Следующий шаг — отзыв U и выбор idle; новую работу автоматически не начинать.
warrior_format_v1/idle-1/death-2 прежние; остальные классы не заменены.
Сохранять core/preview/live/worker/queue/RNG/save/frozen. Без push/sidebar/расписаний.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit; после этапа незакоммичены только они.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261023-13.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт:HEAD,результат,docs/artifacts,остаток,
ограничения,проверки и это же правило передачи. Чат автоматически не создавать.
