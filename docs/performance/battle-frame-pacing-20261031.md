# Диагностика вывода кадров — 2026-10-31

Main; база `8fdf1d882ca12eb9748291fe7f82b017a1708e27`.
Продолжение [длительного боя с 32 персонажами](battle-soak-20261031.md).
Игровой runtime и настройки не менялись. Цель стабильных 60 FPS остаётся открытой.

## Что удалось установить

В предыдущем пятираундовом бою было 44 интервала PresentMon >20 мс.
Проверка исходного CSV показала: каждый соответствующий кадр завершил GPU render
ещё за 9,490–15,165 мс **до показа предыдущего кадра**. Строки непрерывны,
один PID/swapchain, `Dropped=0`; разности времён показа совпадают с записанными
интервалами. Следовательно, эти выбросы возникли после готовности кадров.
Это не определяет виновный компонент, процесс или драйвер.

Обнаружен пробел воспроизводимости: два дисплея 144,003 и 60 Гц, а прежний
runner не записывал фактический экран. Проверка текущей конфигурации показала:
default и явный `--screen 1` открывают окно 1280×850 на основном экране 60 Гц;
`--screen 0` — на экране 144 Гц. Выбран NVIDIA RTX 3050 Laptop.
Это уточнение текущего запуска, не ретроспективное доказательство положения
каждого прежнего окна и не доказанная причина пиков.

Новый контроль: явно screen 1, 32 фигуры, 3600 кадров покоя, тот же Mobile/D3D12
и VSync. Аппаратного ввода не было. Одновременно записаны PresentMon и события
DxgKrnl/DWM/DXGI через отдельный непостоянный ETW session; обе сессии остановлены.

| Измеритель | Кадров | p95, мс | p99, мс | max, мс | >20 мс |
|---|---:|---:|---:|---:|---:|
| Engine, steady idle | 3600 | 18,287 | 19,142 | 22,982 | 15 |
| PresentMon, steady после краевых исключений | 3556 | 16,780 | 18,271 | 22,474 | 15 |

Все 15 длинных интервалов сопоставлены с событиями **DxgKrnl VSyncDPC**
для NVIDIA-адаптера/target 4355. Разность соседних времён событий и их
FrameQPCTime также составляет 20,146–22,474 мс; FrameNumber увеличивается на 1.
Кадр к этому моменту готов за 29,926–31,264 мс до показа предыдущего.
Сопоставление CSV с 3723 DXGI PresentStart имеет сдвиг на одну начальную запись;
разброс преобразования абсолютного времени 0,0252 мс. Ошибка сопоставления
15 событий VSyncDPC с reported display time <0,001 мс.

Это локализует вариацию во времени событий вывода после render. PresentMon
сам использует sync DPC для screen time в этих режимах: совпадение не является
вторым независимым измерителем дисплея. Физический scanout и первопричина
не установлены; нельзя объявить пики просто ошибкой измерения или исправленными.
Неподвижная сцена воспроизводит проблему, но не заменяет нагрузочную проверку боя.
Инструментированный запуск предназначен для диагностики, не для приёмки FPS.

## Изменение тестов

`test_battle_action_performance` теперь записывает display metadata и adapter:
экраны/Hz/DPI/scale, фактический экран/позицию/размер/режим окна и max_fps.
Soak сохраняет display также в initial/final view state. Запросы выполняются
до/после измерения, не каждый кадр. Headless возвращает пустой список экранов
без вызова оконных API. Выбор экрана, FPS и VSync тестом не меняются.

PASS: Godot import/parse в изолированном проекте; metadata probes headless и
screen 1; независимое ревью diff APPROVE. CSV/ETW-выводы получили
APPROVE_WITH_LIMITATIONS. Предыдущие core/launcher/presentation проверки
не повторялись: боевой код не менялся. Full/F5/DPI/другой GPU и прежняя
HUD/lifecycle/цветовая/Колода/арт-приёмка остаются открытыми.

## Необходимый следующий шаг

WPR `CPU + GPU` отказал с `0xc5585011`: нет права Profile system performance
(`SeSystemProfilePrivilege`). Оно отсутствует в текущем токене. Пользовательские
ETW-события доступны, но не дают нужного контекста CPU scheduling/ISR/DPC/стеков.
Политики, права и драйверы не менялись; автоматическое повышение не выполнялось.

Подготовлен локальный helper:
`test_reports/battle-frame-pacing-20261031/capture_system_trace.py`.
Он запускает 60 с покоя с 32 фигурами в подготовленном изолированном проекте
на screen 1 и останавливает только свой именованный WPR instance в finally.
Отдельный APPDATA передаётся только дочернему Godot. Это диагностический сбор,
не изменение игры. Реальный elevated-путь ещё не выполнен.

Из терминала администратора на этом компьютере:

```powershell
python D:\Games\into-de-dung\test_reports\battle-frame-pacing-20261031\capture_system_trace.py
```

Без запуска можно проверить команды с `--plan-only`. Python parse, реальный
отказ без admin и mock normal/start failure/game timeout cleanup прошли;
независимое ревью helper APPROVE. Старый экспериментальный PS helper не является
предлагаемым путём; политику исполнения Windows PowerShell не ослабляли.
После получения ETL требуется связать длинные интервалы с ISR/DPC/CSwitch,
выбрать подтверждённое исправление и снова провести длительный бой.

## Артефакты и источники

Каталог `test_reports/battle-frame-pacing-20261031/`:
`present-readiness.json`, `display-*.log`, `metadata-*.log`, `import.log`,
`idle32-screen1-events.*`, `idle32-screen1-events-present.csv`,
`idle32-screen1-selected.xml`, `event-correlation.json`, `analyze_events.py`,
`run_event_probe.py`, `capture-helper-validation.json`, `validation.json`, `review.md`.
ETL и полный CSV сохранены; строки startup/planner/EOF не удаляются из raw data.
Системный CPU/GPU ETL пока отсутствует. Чужие 33 файла сохранены по SHA-256.

Семантика: [PresentMon v1 CSV](https://github.com/GameTechDev/PresentMon/blob/v1.9.2/README.md#csv-columns),
[обработка sync DPC в PresentMon](https://github.com/GameTechDev/PresentMon/blob/main/PresentData/PresentMonTraceConsumer.cpp),
[право системного профилирования](https://learn.microsoft.com/en-us/windows/win32/secauthz/privilege-constants),
[WPR](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options),
[непостоянная ETW-сессия logman](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/logman-create-trace),
[DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html).
