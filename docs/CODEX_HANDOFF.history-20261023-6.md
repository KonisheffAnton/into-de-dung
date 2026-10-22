# Передача — 2026-10-23: death-2 и новый эталон персонажей
D:\Games\into-de-dung; main; base b2d78510f7c3216f01ebf9bbc32d3c4f4a878e7f.
U выбрал death-2 «Колено, затем вперёд» и назначил нового воина эталоном
формата всех следующих персонажей. [Правила/выбор](ART_DIRECTION.md#новый-эталон-формата-всех-персонажей--2026-10-23),
[эталон](../assets/art_presets/approved/warrior_format_v1/README.md).
В игре death-2 получает только enemy-warrior/Защитник:17 PNG128² по150мс,
2,55с без повтора/паузы галереи. Общий Tween, прежние mirror/anchor71,83/scale0.8,
idle-1; invalid resource→generic. Fall/VOID/обвал и прочие классы прежние.
[Ассеты](../assets/art_presets/trials/enemy_warrior_death_v1/README.md),
[контракт](BATTLE_VISUAL_SCENE_CONTRACT.md#новый-вражеский-воин--2026-10-23),
[отчёт/рендер/GIF](art/enemy-warrior-death-20261023/README.md).
Проверки: initial13PASS/1FAIL; исправлены новые assertions, runtime неизменен.
Повторный parse PASS, death_routes889/0, rogue_routes622/0; вместе со смежными
проверками14 зелёных итоговых gates. Render audit107/0,17 исходников byte-exact.
Итоговое независимое ревью APPROVE. Full/core и ручная F5/editor/DPI/GPU
не заявлены. Выбор формата/клипа U принят; игровые переходы ждут ручной оценки.
Новых генераций/расхода нет. Массовой замены остальных классов не было.
Следующий шаг — отзыв U о смерти или отдельное поручение следующего персонажа;
автоматически не начинать. Core/preview/live/worker/queue/RNG/save/frozen прежние.
Остальные прежние вопросы/пробы — в архивных передачах, не новый backlog этапа.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit. Без push/sidebar/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261023-5.md), [HISTORY](HISTORY.md).
После этапа — проверки и локальный Conventional Commit; короткий HANDOFF,
прежний побайтно в отдельный архив+HISTORY. В финале/при блокере предложить
новый чат и полный промпт: HEAD,результат,docs/artifacts,остаток,ограничения,
проверки и это же правило передачи. Чат автоматически не создавать.
