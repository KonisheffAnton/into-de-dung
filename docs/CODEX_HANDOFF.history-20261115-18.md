# Передача — 2026-11-15: анимации Рваноуха

D:/Games/into-de-dung; main; база cb88eb28857f926ec62abfd8d1dd541b8926723f.
U передал выбранного Рваноуха с рваной одеждой в стандартный animation pipeline.
Нативный RGBA256², силуэт101px против152px Воина; anchor(128,200).
PixelLab:3 idle +3 атаки +3 смерти,297 raw PNG,45 генераций.
[Пакет/галерея/GIF/проверки](art/rvanoukh-animation-20261115/README.md).
Структура/byte integrity PASS, независимое APPROVE как пакет для выбора.
Quality FAIL только death1: кластер у края, карантин; остальные8 edge-clean.
Стыки idle/атак не точные; выбор U, посадка/F5 и runtime-интеграция открыты.
Пример ведущего2/2/3 не выбор U. Новые позы только PixelLab, raw сохранены.
Живые pause/step/scrub/speed/hold/квадратный zoom проверены; blob-ссылка
исходника блокируется IAB. Локальные PNG/GIF сохранены. Runtime не менялся.

Параллельный cb88eb28 сохранён: Выносливость10–14→равновесие5,15–19→6,
далее шаг5; ниже нейтрали прежний floor, steady+2 отдельно; каталог4 та же формула.
Владельцы CHARACTER_ATTRIBUTES_V1/BATTLE_PRESENTATION_REWORK/ARCHITECTURE/TESTING;
[проверки этапа](art/balance-vitals-20261115/endurance-step5.md):5549/0, APPROVE.
Это не новый прогон; нынешний этап не запускал Godot/full/F5/Editor/DPI/performance.
Приёмка полос и кузнеца U открыта;60FPS не заявлены; H2–H5 не начинать.
Кузнец e7abaa9d: art/hub-smith-implementation-20261115/.
Прежняя панцирная серия Костяша отклонена; история/выборы — ART_DIRECTION.
Атаки Воина: art/warrior-attack-single-five-20261114/, выбор/шов открыты.
Остаток: читаемость/стыки/стрела4/performance/HUD/Колода; presentation141/2,
forecast26/3 не повторены; команда3, будущий лимит Q.

Dirty main_menu.tscn и art/battlefield-reference-03-20261017 — чужие, не трогать;
33 защищённых файла сверяются в handoff-audit.json пакета. Без push.
Сохранить core/preview/queue/RNG/save/frozen,5классов F5, PLAYER вправо/ENEMY
влево, возврат после атаки; инициативы нет. Каталоги1–3 не мигрировать.
Один isolated runner, без root import/служб/драйверов/фокуса ОС/sidebar/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261115-17.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD,результат,docs/artifacts,остаток,ограничения,проверки
и это же правило. Чат автоматически не создавать.
