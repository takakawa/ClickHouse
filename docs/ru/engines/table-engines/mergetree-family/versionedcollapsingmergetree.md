---
slug: /ru/engines/table-engines/mergetree-family/versionedcollapsingmergetree
sidebar_position: 37
sidebar_label: VersionedCollapsingMergeTree
---

# VersionedCollapsingMergeTree {#versionedcollapsingmergetree}

Движок:

-   Позволяет быстро записывать постоянно изменяющиеся состояния объектов.
-   Удаляет старые состояния объектов в фоновом режиме. Это значительно сокращает объём хранения.

Подробнее читайте в разделе [Collapsing](#table_engines_versionedcollapsingmergetree).

Движок наследует функциональность от [MergeTree](mergetree.md#table_engines-mergetree) и добавляет в алгоритм слияния кусков данных логику сворачивания (удаления) строк. `VersionedCollapsingMergeTree` предназначен для тех же задач, что и [CollapsingMergeTree](collapsingmergetree.md), но использует другой алгоритм свёртывания, который позволяет вставлять данные в любом порядке в несколько потоков. В частности, столбец `Version` помогает свернуть строки правильно, даже если они вставлены в неправильном порядке. `CollapsingMergeTree` требует строго последовательную вставку данных.

## Создание таблицы {#sozdanie-tablitsy}

``` sql
CREATE TABLE [IF NOT EXISTS] [db.]table_name [ON CLUSTER cluster]
(
    name1 [type1] [DEFAULT|MATERIALIZED|ALIAS expr1],
    name2 [type2] [DEFAULT|MATERIALIZED|ALIAS expr2],
    ...
) ENGINE = VersionedCollapsingMergeTree(sign, version)
[PARTITION BY expr]
[ORDER BY expr]
[SAMPLE BY expr]
[SETTINGS name=value, ...]
```

Подробности про `CREATE TABLE` смотрите в [описании запроса](../../../engines/table-engines/mergetree-family/versionedcollapsingmergetree.md).

**Параметры движка**

``` sql
VersionedCollapsingMergeTree(sign, version)
```

-   `sign` — Имя столбца с типом строки: `1` — строка состояния, `-1` — строка отмены состояния.

        Тип данных столбца должен быть `Int8`.

-   `version` — имя столбца с версией состояния объекта.

        Тип данных столбца должен быть `UInt*`.

**Секции запроса**

При создании таблицы `VersionedСollapsingMergeTree` используются те же [секции](mergetree.md) запроса, что и при создании таблицы `MergeTree` .

<details markdown="1">

<summary>Устаревший способ создания таблицы</summary>

    :::danger "Внимание"
    Не используйте этот метод в новых проектах. По возможности переключите старые проекты на метод, описанный выше.
    :::
    
``` sql
CREATE TABLE [IF NOT EXISTS] [db.]table_name [ON CLUSTER cluster]
(
    name1 [type1] [DEFAULT|MATERIALIZED|ALIAS expr1],
    name2 [type2] [DEFAULT|MATERIALIZED|ALIAS expr2],
    ...
) ENGINE [=] VersionedCollapsingMergeTree(date-column [, sampling_expression], (primary, key), index_granularity, sign, version)
```

Все параметры, за исключением `sign` и `version` имеют то же значение, что и в `MergeTree`.

-   `sign` — Имя столбца с типом строки: `1` — строка состояния, `-1` — строка отмены состояния.

        Тип данных столбца — `Int8`.

-   `version` — имя столбца с версией состояния объекта.

        Тип данных столбца должен быть `UInt*`.

</details>

## Сворачивание (удаление) строк {#table_engines_versionedcollapsingmergetree}

### Данные {#dannye}

Рассмотрим ситуацию, когда необходимо сохранять постоянно изменяющиеся данные для какого-либо объекта. Разумно иметь одну строку для объекта и обновлять эту строку при каждом изменении. Однако операция обновления является дорогостоящей и медленной для СУБД, поскольку требует перезаписи данных в хранилище. Обновление неприемлемо, если требуется быстро записывать данные, но можно записывать изменения в объект последовательно следующим образом.

Используйте столбец `Sign` при записи строки. Если `Sign = 1`, то это означает, что строка является состоянием объекта, назовём её строкой состояния. Если `Sign = -1`, то это означает отмену состояния объекта с теми же атрибутами, назовём её строкой отмены состояния. Также используйте столбец `Version`, который должен идентифицировать каждое состояние объекта отдельным номером.

Например, мы хотим рассчитать, сколько страниц пользователи посетили на каком-либо сайте и как долго они там находились. В какой-то момент времени мы записываем следующую строку состояния пользовательской активности:

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         5 │      146 │    1 │       1 |
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
```

Через некоторое время мы регистрируем изменение активности пользователя и записываем его следующими двумя строками.

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         5 │      146 │   -1 │       1 |
│ 4324182021466249494 │         6 │      185 │    1 │       2 |
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
```

Первая строка отменяет предыдущее состояние объекта (пользователя). Она должна копировать все поля отменяемого состояния за исключением `Sign`.

Вторая строка содержит текущее состояние.

Поскольку нам нужно только последнее состояние активности пользователя, строки

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         5 │      146 │    1 │       1 |
│ 4324182021466249494 │         5 │      146 │   -1 │       1 |
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
```

можно удалить, сворачивая (удаляя) устаревшее состояние объекта. `VersionedCollapsingMergeTree` делает это при слиянии кусков данных.

Чтобы узнать, зачем нам нужны две строки для каждого изменения, см. раздел [Алгоритм](#table_engines-versionedcollapsingmergetree-algorithm).

**Примечания по использованию**

1.  Программа, которая записывает данные, должна помнить состояние объекта, чтобы иметь возможность отменить его. Строка отмены состояния должна содержать копии полей первичного ключа и копию версии строки состояния и противоположное значение `Sign`. Это увеличивает начальный размер хранилища, но позволяет быстро записывать данные.
2.  Длинные растущие массивы в столбцах снижают эффективность работы движка за счёт нагрузки на запись. Чем проще данные, тем выше эффективность.
3.  `SELECT` результаты сильно зависят от согласованности истории изменений объекта. Будьте точны при подготовке данных для вставки. Вы можете получить непредсказуемые результаты с несогласованными данными, такими как отрицательные значения для неотрицательных метрик, таких как глубина сеанса.

### Алгоритм {#table_engines-versionedcollapsingmergetree-algorithm}

Когда ClickHouse объединяет куски данных, он удаляет каждую пару строк, которые имеют один и тот же первичный ключ и версию и разный `Sign`. Порядок строк не имеет значения.

Когда ClickHouse вставляет данные, он упорядочивает строки по первичному ключу. Если столбец `Version` не находится в первичном ключе, ClickHouse добавляет его к первичному ключу неявно как последнее поле и использует для сортировки.

## Выборка данных {#vyborka-dannykh}

ClickHouse не гарантирует, что все строки с одинаковым первичным ключом будут находиться в одном результирующем куске данных или даже на одном физическом сервере. Это справедливо как для записи данных, так и для последующего слияния кусков данных. Кроме того, ClickHouse обрабатывает запросы `SELECT` несколькими потоками, и не может предсказать порядок строк в конечной выборке. Это означает, что если необходимо получить полностью «свернутые» данные из таблицы `VersionedCollapsingMergeTree`, то требуется агрегирование.

Для завершения свертывания добавьте в запрос секцию `GROUP BY` и агрегатные функции, которые учитывают знак. Например, для расчета количества используйте `sum(Sign)` вместо`count()`. Чтобы вычислить сумму чего-либо, используйте `sum(Sign * x)` вместо`sum(х)`, а также добавьте `HAVING sum(Sign) > 0` .

Таким образом можно вычислять агрегации `count`, `sum` и `avg`. Агрегация `uniq` может вычисляться, если объект имеет хотя бы одно не свернутое состояние. Невозможно вычислить агрегации `min` и `max` поскольку`VersionedCollapsingMergeTree` не сохраняет историю значений для свернутых состояний.

Если необходимо выбирать данные без агрегации (например, проверить наличие строк, последние значения которых удовлетворяют некоторым условиям), можно использовать модификатор `FINAL` для секции `FROM`. Такой подход неэффективен и не должен использоваться с большими таблицами.

## Пример использования {#primer-ispolzovaniia}

Данные для примера:

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         5 │      146 │    1 │       1 |
│ 4324182021466249494 │         5 │      146 │   -1 │       1 |
│ 4324182021466249494 │         6 │      185 │    1 │       2 |
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
```

Создание таблицы:

``` sql
CREATE TABLE UAct
(
    UserID UInt64,
    PageViews UInt8,
    Duration UInt8,
    Sign Int8,
    Version UInt8
)
ENGINE = VersionedCollapsingMergeTree(Sign, Version)
ORDER BY UserID
```

Вставка данных:

``` sql
INSERT INTO UAct VALUES (4324182021466249494, 5, 146, 1, 1)
```

``` sql
INSERT INTO UAct VALUES (4324182021466249494, 5, 146, -1, 1),(4324182021466249494, 6, 185, 1, 2)
```

Мы используем два запроса `INSERT` для создания двух различных кусков данных. Если мы вставляем данные с помощью одного запроса, ClickHouse создаёт один кусок данных и не будет выполнять слияние.

Получение данных:

``` sql
SELECT * FROM UAct
```

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         5 │      146 │    1 │       1 │
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         5 │      146 │   -1 │       1 │
│ 4324182021466249494 │         6 │      185 │    1 │       2 │
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
```

Что мы видим и где сворачивание?
Мы создали два куска данных, используя два запроса `INSERT`. Запрос `SELECT` был выполнен в два потока, и результатом является случайный порядок строк.
Свертывание не произошло, поскольку части данных еще не были объединены. ClickHouse объединяет части данных в неизвестный момент времени, который мы не можем предсказать.

Поэтому нам нужна агрегация:

``` sql
SELECT
    UserID,
    sum(PageViews * Sign) AS PageViews,
    sum(Duration * Sign) AS Duration,
    Version
FROM UAct
GROUP BY UserID, Version
HAVING sum(Sign) > 0
```

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Version─┐
│ 4324182021466249494 │         6 │      185 │       2 │
└─────────────────────┴───────────┴──────────┴─────────┘
```

Если нам не нужна агрегация, но мы хотим принудительно выполнить свёртку данных, то можно использовать модификатор `FINAL` для секции `FROM`.

``` sql
SELECT * FROM UAct FINAL
```

``` text
┌──────────────UserID─┬─PageViews─┬─Duration─┬─Sign─┬─Version─┐
│ 4324182021466249494 │         6 │      185 │    1 │       2 │
└─────────────────────┴───────────┴──────────┴──────┴─────────┘
```

Это очень неэффективный способ выбора данных. Не используйте его для больших таблиц.
