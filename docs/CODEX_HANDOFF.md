# Передача — 2026-11-04: анимации опасностей и шипы

D:/Games/into-de-dung; main; base87492941c420a4b0e0e13b19f21d96b3d8a0889a.
По U получены [30 анимаций PixelLab](art/hazard-animations-20261104/README.md):
по5 для огня29/23/24/22, кислоты01 «Зелёная плёнка», кальтропов03 (блики).
30 completed,966 PNG256²:29×33 PixMiniMax+9 кадров v3 fire22-01;
153 генерации. Исходники/входы/запросы/SHA/usage/наблюдения и галерея сохранены.
Также готовы [10 пар выдвижных ловушек](art/retractable-spike-traps-20261104/README.md):
слева спрятаны, справа выдвинуты;10 исходных PNG image_gen и галерея.
Ориентир — art/current-tile-reference-20261103/; направление — ART_DIRECTION.

Технически PASS:966 API-byte matches,10 исходных пар/SHA, обе автономные
галереи/управление/390px; diff/ссылки/архив; техревью APPROVE. Art NOT ACCEPTED:
PixelLab часто поднимает огонь, меняет камень/палитру. Margin FAIL fire24-01:
9 кадров касаются края холста. Ни один последний кадр не совпал по RGBA с входом.
Наблюдения в галерее не гарантируют просмотр всех кадров; петли/качество открыты.
Отчёты: test_reports/hazard-animations-20261104/, retractable-spike-traps-20261104/,
hazard-animation-spikes-20261104/. Godot/full/core/F5 не запускались; внедрения нет.

Ранее внедрена кислота05/01 без камня; [свидетельства](art/acid01-integration-20261104/README.md).
BATTLE_VISUAL_SCENE_CONTRACT/ENVIRONMENT_HAZARDS_V1 — владельцы поведения.
Прежние проверки и APPROVE не повторялись. Остаток: ручные F5/движение/zoom/DPI,
стыки/посадка/качество/performance, край стрелы способности4 Лучницы;
presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода, hazards_ui105/2.
Дальше — выбор/отзыв U; новую генерацию/анимацию/интеграцию не начинать.
33 чужих файла scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Сохранять core/preview/queue/RNG/save/frozen, пять классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса/push/sidebar tasks/расписаний.
[Прежняя передача](CODEX_HANDOFF.history-20261104-5.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
