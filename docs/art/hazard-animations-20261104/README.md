# Пробы анимации опасностей · 2026-11-04

Отдельная серия из 30 концептуальных циклов PixelLab: по пять для `fire-low-29`, `fire-low-23`, `fire-low-24`, `fire-low-22`, `acid-01` («Зелёная плёнка») и `caltrops-03` («Воронёные иглы»). Ключи и тексты движений записаны в [requests.json](requests.json). Результаты не предназначены для автоматической интеграции в игру; художественная приёмка остаётся за пользователем.

Каждый исходный PNG сохранён без изменения в `model/<sourcekey>/source-original.png`. Вход `input-256.png` — весь кадр RGBA 1254², уменьшенный до 256² Pillow LANCZOS без кропа и ретуши. Хеши и преобразование — в `model/<sourcekey>/transform.json`. Запросы также сохранены вне Git в `C:/Users/Aston/.codex/generated_images/hazard-animations-20261104/pixellab/<key>/request.json`. Токен находится только в DPAPI-хранилище и передаётся Bearer на официальный `https://api.pixellab.ai`.

Снимок схемы: `C:/Users/Aston/.codex/generated_images/hazard-animations-20261104/openapi-20261104.json`; исходный баланс: `balance-before.json` там же. Перед каждым POST bridge повторно читает живую схему и сохраняет её в `openapi-before-post.json` или `openapi-before-post-<key>.json`. Для каждой попытки до POST создаётся `submit-started.json`; неопределённый результат не отправляется повторно. Возобновлять по принятому `background_job_id` через GET. Максимум три активных задания.

После первых шести клипов 14 ещё не отправленных fire-запросов получили более строгие промпты и captions. Старые шесть запросов и десять acid/caltrops-запросов сохранены; прежние и новые тексты/хеши перечислены в [prompt-revision-01.json](prompt-revision-01.json). Один `fire22-01` отправлен через официальный `animate-with-text-v3` (8 заказанных кадров, 9 полученных, `drift_threshold=0` только для цвета), с отдельной записью [v3-запроса](prompt-revision-02-v3.json) и [фактического ответа](prompt-revision-03-v3-result.json). Остальные 29 клипов используют PixMiniMax и возвращают по 33 кадра. Все 30 завершены; [usage](usage.json) — 29×5 + 8 = 153 генерации, баланс после серии `balance-after-all.json` вне Git — 4847/5000. Визуальная оценка — [probe-review.md](probe-review.md), по каждому клипу также в [галерее](gallery.html).

Технический [экспорт](pixellab-validation.json) и [проверка](validation.json) прошли: 966/966 PNG-кадров совпали с исходными байтами API, источники и входы сохранены, первые видимые кадры совпали с входом. Только первый кадр v3 совпал также по полному RGBA; ни один последний кадр не совпал с входом по RGBA. Все кадры имеют прозрачную область, но проверка отступов — **FAIL**: в `fire24-01` девять промежуточных кадров содержат крупную серую массу с касанием края холста. Не считать высоту огня, неподвижность боковин, бесшовность или художественную приёмку техническим PASS.

## Повторная проверка сохранённого результата

[Независимое техническое ревью](review.md): APPROVE после исправления описания
fire29-01; художественные ограничения остаются открытыми.

Из корня репозитория:

```powershell
python docs/art/hazard-animations-20261104/validate_prepared.py
python docs/art/hazard-animations-20261104/export_pixellab.py
python docs/art/hazard-animations-20261104/validate_package.py --verify-raw
python docs/art/hazard-animations-20261104/measure_drift.py
python docs/art/hazard-animations-20261104/summarize_usage.py
python docs/art/hazard-animations-20261104/build_gallery.py
node docs/art/hazard-animations-20261104/check_gallery.cjs
```

Промежуточный экспорт записывал отдельные `pixellab-validation-partial.json`, `validation-partial.json` и `gallery-partial.html`, пока серия была неполной. Финальный автономный `gallery.html` содержит 30 карточек и шесть групп; проверка браузера при 390 px сохранена в `test_reports/hazard-animations-20261104/browser-validation.json`.

Экспорт принимает только `completed` с совпавшим admission ID и сохраняет исходные PNG-байты кадров. Для каждого клипа строятся GIF и PNG-лист; автономный `gallery.html` содержит управление паузой, кадром, скоростью, масштабом и фоном. GIF-тайминг 100 мс/кадр нужен только для просмотра. Валидатор проверяет происхождение, фактическое число кадров каждого endpoint, размеры, alpha, листы, GIF, исходные байты API и первый видимый кадр. Галерея проверена также при ширине 390 px. Эти проверки не подтверждают неподвижность камня/предметов, качество петли или художественную приёмку.
