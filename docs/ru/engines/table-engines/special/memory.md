---
slug: /ru/engines/table-engines/special/memory
sidebar_position: 44
sidebar_label: Memory
---

# Memory {#memory}

Хранит данные в оперативке, в несжатом виде. Данные хранятся именно в таком виде, в каком они получаются при чтении. То есть, само чтение из этой таблицы полностью бесплатно.
Конкурентный доступ к данным синхронизируется. Блокировки короткие: чтения и записи не блокируют друг друга.
Индексы не поддерживаются. Чтение распараллеливается.
За счёт отсутствия чтения с диска, разжатия и десериализации данных удаётся достичь максимальной производительности (выше 10 ГБ/сек.) на простых запросах. (Стоит заметить, что во многих случаях, производительность движка MergeTree, почти такая же высокая.)
При перезапуске сервера данные из таблицы исчезают и таблица становится пустой.
Обычно, использование этого движка таблиц является неоправданным. Тем не менее, он может использоваться для тестов, а также в задачах, где важно достичь максимальной скорости на не очень большом количестве строк (примерно до 100 000 000).

Движок Memory используется системой для временных таблиц - внешних данных запроса (смотрите раздел «Внешние данные для обработки запроса»), для реализации `GLOBAL IN` (смотрите раздел «Операторы IN»).
