---
slug: /ru/sql-reference/aggregate-functions/reference/grouparray
sidebar_position: 110
---

# groupArray {#agg_function-grouparray}

Синтаксис: `groupArray(x)` или `groupArray(max_size)(x)`

Составляет массив из значений аргумента.
Значения в массив могут быть добавлены в любом (недетерминированном) порядке.

Вторая версия (с параметром `max_size`) ограничивает размер результирующего массива `max_size` элементами.
Например, `groupArray(1)(x)` эквивалентно `[any(x)]`.

В некоторых случаях, вы всё же можете рассчитывать на порядок выполнения запроса. Это — случаи, когда `SELECT` идёт из подзапроса, в котором используется `ORDER BY`.
