# Выбранная смерть вражеского воина: death-2

U2026-10-23 выбрал «death-2 — Колено, затем вперёд» из
[трёх вариантов](../../../../docs/art/warrior-death-kneel-round2-20261023/README.md).
PixelLab job `6c1f9328-8311-4a7d-b01d-48570a5426f8`, исходный пакет
`C:/Users/Aston/.codex/generated_images/warrior-death-kneel-round2-20261023/pixellab2/death-2/`.
[source-manifest.json](source-manifest.json) содержит исходные пути и SHA17 PNG128².
Все файлы скопированы побайтно; первый кадр совпадает с игровым still/idle.

`death_frames.tres`:17×150мс=2,55с, non-loop; тайминг взят из выбранного превью.
API времени не задавал. Пауза1200мс последнего кадра в сравнительной галерее
не входит в игровой клип. Рисунок сначала опускается на колено, затем ложится;
заголовок сохраняет имя выбранного варианта.

Только ENEMY+warrior с `enemy_warrior_art_enabled` получает новый ресурс.
Тот же EnemyWarriorIdleSprite, anchor(71,83), mirror(-1,1), ArtRoot0.8 и native128²
без brighter palette/cloth. Root/тень/HUD не отражаются и не смещаются.
Все кадры сохраняют общую опору; силуэт падения не центрируется заново.
Нет локального таймера, дополнительного вращения или fade.
Общий Tween ведёт кадры, speed/pause/skip/cancel; after/тело публикуются после клипа.
Fall/VOID/HAZARD/обвал сохраняют свой путь. Null/неполный ресурс, нулевая скорость
или отсутствующая текстура дают общий fallback с текущим новым рисунком.

[Жизненный цикл](../../../../docs/BATTLE_VISUAL_SCENE_CONTRACT.md#новый-вражеский-воин--2026-10-23),
[проверки внедрения](../../../../docs/art/enemy-warrior-death-20261023/README.md),
[новый эталон формата](../../approved/warrior_format_v1/README.md).
