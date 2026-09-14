# P08 — независимое ревью spatial-пакета

2026-09-14. Редакция 2. **APPROVE**.
Это приёмка спецификации; runtime P08 не реализован этим этапом.

## Результат и согласование

Подготовлен самодостаточный P08_SPATIAL_TASK с 22 allowed paths, контрактами
представления/снимков/профилей/очереди и 17 группами приёмки S01–S17.
Новые profiles включаются явно в headless harness; UI/AI/Flow не подключаются.

Пользователь подтвердил целиком итоговые уточнения:
- Добровольный подъём до1; спуск любой, урон только при перепаде>1.
- Обычный переход на+1 стоит ВСЕГО2, на+0.5 ВСЕГО1: это terrain cost плюс
  полные уровни подъёма. Полуровень не делает вход бесплатным.
- Push поднимает до0.5, падение от Push на1 ранит. Для обоих видов падения
  считаются все полные уровни текущего ребра, без дробной части/накопления.
- Дальность1 достигает первого соседа,2 — первого/второго по прямой;
  требуется d+floor(abs перепад), без диагоналей. Через персонажа — только друга.
  Особое правило края уступа заменено доступностью и дальностью.
- HP/impact используют линейные +/-20% за уровень, +/-10% за полуровень.
  HP множитель до брони; HP/положительный impact минимум1, исходный impact0
  и immunity сохраняются. Старые x1.5 и /1.5 для баланса отменены.
- Высотный множитель относится к удару, не к отдельному collision/fall damage.

Ограничение ведущего для первого технического профиля: монотонный рельеф прямой
линии. Промежуточный VOID/немонотонный рельеф дают явное unsupported; это не
утверждение игрового запрета всех атак через ямы/гребни. Общий LOS отложен.

## Проверенный вход

Base/main HEAD: c12cbcacf70f1b04018659d7cbf6f90c4ba39ba4.
Исходный status совпал с p07-final-audit. Принятая реализация P07 сверена по
26/26 implementation hashes и 10/10 final audit hashes. Наложение принятой
реализации/финальных addenda дало 167/167 effective matches и6/6 historical
local artifacts. В старом P07_DEPENDENCIES 131 прежний файл неизменен,
9 заменены принятым P07 (5 runtime/tests и4 финальных документационных дополнения).
Исторические manifests/frozen пакеты не переписаны.

Новый P08_DEPENDENCIES фиксирует 256 файлов текущего рабочего дерева и22 local
artifacts. Все проверены ведущим и независимым reviewer. Чистого checkout мало:
dirty P01/P02/P06, untracked snapshot scripts и документы остаются зависимостями.
HANDOFF исключён как mutable; принятый текст P07 сохранён точным byte suffix и
отдельным handoff-before.md, его исходный hash закреплён в baseline.

## Frozen hashes редакции 2

| Файл / точное представление | SHA-256 |
|---|---|
| P08_SPATIAL_TASK.md | `FB67C9EAAA46159174E13F382ADA40AF2CCDD4134BFC55F1045371FA3DC387A4` |
| P08_DEPENDENCIES.json — принятые рабочие bytes | `F08ED3F8D6A76038A753360DF8455C7410B9257F6A0D7B36F972729BF0683B98` |
| P08_DEPENDENCIES.json — Git LF checkout bytes | `7B5889642F36DD91E6418DBAE185361E0AADBBAC85ED81D84A819EE0AA16BAB1` |

Для TASK допустим только первый hash, для DEPENDENCIES — ровно один из двух
указанных exact hashes. Это не общее разрешение игнорировать переводы строк.
Все files/local_artifacts внутри manifest требуют ровно своих записанных hashes.

После APPROVE TASK/DEPENDENCIES на диске не редактировались. .gitattributes требует
LF для JSON, поэтому Git нормализует 1256 CRLF пар принятого файла при staging:
50503 ->49247 bytes. Дополнительный read-only reviewer подтвердил, что это только
CRLF->LF, без одиночных CR/других изменений; ожидаемый Git blob
`9c96bfbe18073a8b0482ae5e4762ec41c26d518e`. Оба представления независимо проверены.

## Независимое ревью и проверки ведущего

game_scout / gpt-5.6-luna / low выполнил адресные read-only исследования геометрии,
faction/admission, цены Move и snapshot/provider seams с минимальным контекстом.
Ведущий выбрал additive half bits без смены масштаба целых карт, сохранил
UnitState.height как независимый int64 cache целой части и проверил критические
формулы, source B collision, queue capacity и этапы version/callback guards.

game_reviewer / gpt-5.6-terra / high с fork_turns=none дал первой редакции
REQUEST_CHANGES: ошибочное имя make_geometry_provider не закрывало реальный
make_terrain_only_provider. Редакция2 называет правильный API и требует в S04
проверку обоих прямых legacy provider paths. Повторное fixed review — APPROVE,
блокирующих замечаний нет. Дополнительное byte-provenance review — APPROVE.
Агенты не писали файлы, не делегировали дальше, не запускали Godot и не коммитили.

Ведущий выполнил check-package.ps1, exit0: 256 dependencies/22 local artifacts,
256 прежних рабочих файлов вне HANDOFF и1091 старый отчёт сохранены; исходный
HANDOFF suffix124129 bytes совпал. Allowed22 (18 существующих/4 новых), S01–S17,
6 decimal damage /8 reach /5 fall examples, code fences, residual reverse check
и whitespace/diff checks прошли. Индекс перед staging был пуст.

Артефакты находятся в test_reports/p08-spatial-preparation-20260914/:
baseline.json, handoff-before.md, task-r1.md, dependencies-r1.json,
checks-r1/r2.json, review-manifest-r1/r2.json, independent-review-r1/r2.md,
independent-lf-provenance-review.md и check-package.ps1.
Фиксированный r2 manifest SHA-256:
`E7AB609BE3104AE44FFDBFB2FD1AE86E2AD8EFE4583B33E548F4E45138F698FD`.

Godot в этой документационной подготовке не запускался. 1996 passed /0 failed,
успешные import/startup и45 ObjectDB/18 resources — историческая проверка P07.
После будущей реализации обязательны новые import/startup/runner/S01–S17 и
независимое критическое ревью runtime: snapshots/queue/version guards и replay.
Полный preview, UI/AI/save-game не объявляются реализованными.

## Следующий этап

Отдельное поручение на реализацию P08 редакции2 в сохранённом рабочем дереве.
Начать со свежей проверки HEAD/status, указанных frozen hashes и effective
dependencies. Удобно перейти в новый чат с CODEX_HANDOFF; задачи автоматически
не создавались. Подготовка фиксируется локальным docs commit только из TASK,
DEPENDENCIES и этого REVIEW; HANDOFF обновляется отдельно без staging старого текста.
Push и работа по расписанию не выполнялись.
