---
slug: /ru/engines/table-engines/special/null
sidebar_position: 38
sidebar_label: 'Null'
---

При записи в таблицу типа Null, данные игнорируются. При чтении из таблицы типа Null, возвращается пустота.

Тем не менее, есть возможность создать материализованное представление над таблицей типа Null. Тогда данные, записываемые в таблицу, будут попадать в представление.
