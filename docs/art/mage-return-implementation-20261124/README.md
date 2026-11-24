# Носитель: останки, дух и возвращение — 2026-11-24

Рабочий срез по [HOST_POSSESSION_V1](../../HOST_POSSESSION_V1.md). Смерть сохраняет пространственную привязку; две карты возвращают исходного героя или временную нежить. Явный повторный выбор после боя сохраняется с retry.

Свежий isolated import/startup,28 адресных suites и core PASS; core9428/0. Шесть GPU suites PASS; независимый core и docs review APPROVE. [Локальный отчёт](../../../test_reports/mage-return-implementation-20261124/REPORT.md) содержит manifests, команды, baseline и ограничения.

Дух показан процедурным силуэтом; окончательный арт и баланс не утверждены. Ручные F5/Editor/движение/zoom/DPI и performance не проверены. Full до изменения имел19 отказов и2 тайм-аута; полного зелёного прогона нет. Кадры ниже — автоматический GPU, не пользовательская приёмка.

Кадры поля при180%: [свежие останки](host-corpse-field.png), [кости](host-bones-field.png), [дух](host-spirit-field.png). Останки могут находиться под живым бойцом; у духа нет HP/occupancy.

[Выбор носителя над картой](host-reselection-required.png) и [повтор записи после ошибки](host-reselection-save-retry.png). Кнопки выбора проверяются в пределах viewport1280×850; отказ записи сохраняет прежний профиль и кандидата для retry.

Команды: `python tools/demo/isolate.py --check --only return_effects mage_return host_cards host_expedition host_reselection_ui mage_deck_playthrough core`; визуальные `host_anchor_view host_corpse_input host_ui host_glow mage_deck_ui` через `--render-check`. Финальный широкий адресный набор перечислен в отчёте. Полные логи/снимки изоляции остаются локально в test_reports.
