# PixelLab — пресет попытки 03 (animate-pixminimax, «subtle»)

Результат: `03_animate-pixminimax_subtle_raw.gif`

## Запрос

- **Эндпоинт:** `POST https://api.pixellab.ai/v2/animate-pixminimax`
- **Заголовки:** `Authorization: Bearer <API_TOKEN>`, `Content-Type: application/json`
- **Результат:** асинхронный — ответ содержит `background_job_id`; опрос `GET https://api.pixellab.ai/v2/background-jobs/{background_job_id}` каждые 5–10 с, кадры в `last_response.images`
- **Стоимость:** 2 генерации

## Параметры

| Параметр | Значение |
|---|---|
| `first_frame` | `input_frame_128.png` (PNG, base64) |
| `last_frame` | `input_frame_128.png` — тот же кадр, чтобы цикл замкнулся |
| `frame_count` | `12` |
| `seed` | `0` (случайный) |
| `no_background` | `true` |
| `drift_threshold` | `0` |
| `direction` | `east` |
| `view` | `high top-down` |
| `enhance_prompt` | не передавался (по умолчанию `false`) |

## Промпты

**description**

```text
Extremely subtle idle breathing, barely visible: the chest and shoulders lift by a single pixel and settle back, the head follows one frame later by a single pixel. Everything else holds perfectly still: feet, legs, hips, bow, string and hands keep their exact pixels; the face, eyes, hair outline and ponytail keep their exact shape. No bobbing of the whole body, no swaying, no stepping, no blinking.
```

**subject_description**

```text
an adult female archer with a high dark brown ponytail, olive scarf, brown leather pauldrons, bracers and boots, quiver with white-fletched arrows on her back, holding one wooden bow
```

**initial_pose**

```text
standing in a wide ready stance with knees slightly bent, bow lowered in the hand on the right side of the image, the other arm hanging down
```

## Тело запроса (JSON)

```json
{
  "first_frame": { "type": "base64", "base64": "<input_frame_128.png>", "format": "png" },
  "last_frame":  { "type": "base64", "base64": "<input_frame_128.png>", "format": "png" },
  "description": "Extremely subtle idle breathing, barely visible: the chest and shoulders lift by a single pixel and settle back, the head follows one frame later by a single pixel. Everything else holds perfectly still: feet, legs, hips, bow, string and hands keep their exact pixels; the face, eyes, hair outline and ponytail keep their exact shape. No bobbing of the whole body, no swaying, no stepping, no blinking.",
  "frame_count": 12,
  "seed": 0,
  "no_background": true,
  "drift_threshold": 0,
  "direction": "east",
  "view": "high top-down",
  "subject_description": "an adult female archer with a high dark brown ponytail, olive scarf, brown leather pauldrons, bracers and boots, quiver with white-fletched arrows on her back, holding one wooden bow",
  "initial_pose": "standing in a wide ready stance with knees slightly bent, bow lowered in the hand on the right side of the image, the other arm hanging down"
}
```

## Входной кадр

`input_frame_128.png` — 128×128 RGBA, прозрачный фон, 48 цветов. Персонаж — исходник, переведённый в родное разрешение (118×118 логических пикселей, смещение 5 px от края). Версия со старой тетивой, до исправления.

## Ответ и сборка GIF

- API вернул 13 кадров 128×128: кадр 0 — вход без изменений, кадры 1–12 сгенерированы, кадр 12 ≈ входу.
- GIF: все 13 кадров по порядку без правок, 200 мс на кадр, бесконечный цикл, увеличение ×4 nearest-neighbor до 512×512.

## Примечание

Фактический seed этой генерации не сохранился: в запросе был `seed: 0` (случайный), а задание уже удалено с сервера PixelLab. Повтор с тем же пресетом даст похожий, но не идентичный результат; при повторе seed виден в `last_response.seed`.
