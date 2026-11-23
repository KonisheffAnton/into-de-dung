# Свежий труп — конечный кадр смерти

U2026-11-23 отменил прежний универсальный свежий PL-F3: теперь свежий труп
должен быть последним кадром смерти конкретного персонажа. Владелец решения —
[ENVIRONMENT_D5](../../ENVIRONMENT_D5.md#свежие-трупы-и-кости--2026-11-22).
Этот пакет содержит новые сухие кости и фиксацию решения, без runtime-правки.

Адресная сверка game_scout и ведущего на fca68bb8:

- `scripts/demo/battle_environment_visual.gd`, `_draw_corpses()` / `_draw_corpse()`:
  сейчас общий полигональный fresh/bones, без кадра умершего персонажа.
- `scripts/core/board/combat_environment_state.gd`, `record_death()`:
  сохраняет `source_unit_id`, но не визуальный класс/skin/frame.
  `age_corpses()` уже управляет переходом свежего трупа в кости.
- `scripts/demo/battle_character_skin_visual.gd`, `_draw_skin_clip()`:
  умеет выбрать конец death-клипа в анимации, но текущая видимость skin
  связана с живым юнитом; отдельный corpse-overlay конечный кадр не удерживает.
- `scripts/demo/battle_field_presentation.gd`, `sample_death()`:
  если authored death отсутствует, использует общую подачу смерти.

При внедрении нужно провести выбранный визуальный облик/конечный кадр через
presentation-слой к останкам, сохранив точку опоры, размер и порядок публикации.
Для отсутствующего death-клипа показ конечной позы ещё требует определения.
Проверять не только sample(progress=1), но и останки после финальной публикации,
их замену костями после срока, нежить и отсутствие останков при падении/VOID.
Полезные существующие наборы: test_presentation_environment,
test_environment_visual_contract, test_tamed_troglodyte_visual.
Эти проверки в текущем арт-этапе не запускались.
