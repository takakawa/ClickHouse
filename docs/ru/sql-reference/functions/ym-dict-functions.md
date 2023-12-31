---
slug: /ru/sql-reference/functions/ym-dict-functions
sidebar_position: 59
sidebar_label: "Функции для работы со словарями Яндекс.Метрики"
---

# Функции для работы со словарями Яндекс.Метрики {#ym-dict-functions}

Чтобы указанные ниже функции работали, в конфиге сервера должны быть указаны пути и адреса для получения всех словарей Яндекс.Метрики. Словари загружаются при первом вызове любой из этих функций. Если справочники не удаётся загрузить - будет выкинуто исключение.

О том, как создать справочники, смотрите в разделе «Словари».

## Множественные геобазы {#multiple-geobases}

ClickHouse поддерживает работу одновременно с несколькими альтернативными геобазами (иерархиями регионов), для того чтобы можно было поддержать разные точки зрения о принадлежности регионов странам.

В конфиге clickhouse-server указывается файл с иерархией регионов:
`<path_to_regions_hierarchy_file>/opt/geo/regions_hierarchy.txt</path_to_regions_hierarchy_file>`

Кроме указанного файла, рядом ищутся файлы, к имени которых (до расширения) добавлен символ _ и какой угодно суффикс.
Например, также найдётся файл `/opt/geo/regions_hierarchy_ua.txt`, если такой есть.

`ua` называется ключом словаря. Для словаря без суффикса, ключ является пустой строкой.

Все словари перезагружаются в рантайме (раз в количество секунд, заданное в конфигурационном параметре builtin_dictionaries_reload_interval, по умолчанию - раз в час), но перечень доступных словарей определяется один раз, при старте сервера.

Во все функции по работе с регионами, в конце добавлен один необязательный аргумент - ключ словаря. Далее он обозначен как geobase.
Пример:

``` text
regionToCountry(RegionID) - использует словарь по умолчанию: /opt/geo/regions_hierarchy.txt;
regionToCountry(RegionID, '') - использует словарь по умолчанию: /opt/geo/regions_hierarchy.txt;
regionToCountry(RegionID, 'ua') - использует словарь для ключа ua: /opt/geo/regions_hierarchy_ua.txt;
```

### regionToCity(id\[, geobase\]) {#regiontocityid-geobase}

Принимает число типа UInt32 - идентификатор региона из геобазы Яндекса. Если регион является городом или входит в некоторый город, то возвращает идентификатор региона - соответствующего города. Иначе возвращает 0.

### regionToArea(id\[, geobase\]) {#regiontoareaid-geobase}

Переводит регион в область (тип в геобазе - 5). В остальном, аналогично функции regionToCity.

``` sql
SELECT DISTINCT regionToName(regionToArea(toUInt32(number), 'ua'))
FROM system.numbers
LIMIT 15
```

``` text
┌─regionToName(regionToArea(toUInt32(number), \'ua\'))─┐
│                                                      │
│ Москва и Московская область                          │
│ Санкт-Петербург и Ленинградская область              │
│ Белгородская область                                 │
│ Ивановская область                                   │
│ Калужская область                                    │
│ Костромская область                                  │
│ Курская область                                      │
│ Липецкая область                                     │
│ Орловская область                                    │
│ Рязанская область                                    │
│ Смоленская область                                   │
│ Тамбовская область                                   │
│ Тверская область                                     │
│ Тульская область                                     │
└──────────────────────────────────────────────────────┘
```

### regionToDistrict(id\[, geobase\]) {#regiontodistrictid-geobase}

Переводит регион в федеральный округ (тип в геобазе - 4). В остальном, аналогично функции regionToCity.

``` sql
SELECT DISTINCT regionToName(regionToDistrict(toUInt32(number), 'ua'))
FROM system.numbers
LIMIT 15
```

``` text
┌─regionToName(regionToDistrict(toUInt32(number), \'ua\'))─┐
│                                                          │
│ Центральный федеральный округ                            │
│ Северо-Западный федеральный округ                        │
│ Южный федеральный округ                                  │
│ Северо-Кавказский федеральный округ                      │
│ Приволжский федеральный округ                            │
│ Уральский федеральный округ                              │
│ Сибирский федеральный округ                              │
│ Дальневосточный федеральный округ                        │
│ Шотландия                                                │
│ Фарерские острова                                        │
│ Фламандский регион                                       │
│ Брюссельский столичный регион                            │
│ Валлония                                                 │
│ Федерация Боснии и Герцеговины                           │
└──────────────────────────────────────────────────────────┘
```

### regionToCountry(id\[, geobase\]) {#regiontocountryid-geobase}

Переводит регион в страну. В остальном, аналогично функции regionToCity.
Пример: `regionToCountry(toUInt32(213)) = 225` - преобразовали Москву (213) в Россию (225).

### regionToContinent(id\[, geobase\]) {#regiontocontinentid-geobase}

Переводит регион в континент. В остальном, аналогично функции regionToCity.
Пример: `regionToContinent(toUInt32(213)) = 10001` - преобразовали Москву (213) в Евразию (10001).

### regionToTopContinent (#regiontotopcontinent) {#regiontotopcontinent-regiontotopcontinent}

Находит для региона верхний в иерархии континент.

**Синтаксис**

``` sql
regionToTopContinent(id[, geobase])
```

**Аргументы**

-   `id` — идентификатор региона из геобазы Яндекса. [UInt32](../../sql-reference/functions/ym-dict-functions.md).
-   `geobase` — ключ словаря. Смотрите [Множественные геобазы](#multiple-geobases). [String](../../sql-reference/functions/ym-dict-functions.md). Опциональный параметр.

**Возвращаемое значение**

-   Идентификатор континента верхнего уровня (последний при подъеме по иерархии регионов).
-   0, если его нет.

Тип: `UInt32`.

### regionToPopulation(id\[, geobase\]) {#regiontopopulationid-geobase}

Получает население для региона.
Население может быть прописано в файлах с геобазой. Смотрите в разделе «Встроенные словари».
Если для региона не прописано население, возвращается 0.
В геобазе Яндекса, население может быть прописано для дочерних регионов, но не прописано для родительских.

### regionIn(lhs, rhs\[, geobase\]) {#regioninlhs-rhs-geobase}

Проверяет принадлежность региона lhs региону rhs. Возвращает число типа UInt8, равное 1, если принадлежит и 0, если не принадлежит.
Отношение рефлексивное - любой регион принадлежит также самому себе.

### regionHierarchy(id\[, geobase\]) {#regionhierarchyid-geobase}

Принимает число типа UInt32 - идентификатор региона из геобазы Яндекса. Возвращает массив идентификаторов регионов, состоящий из переданного региона и всех родителей по цепочке.
Пример: `regionHierarchy(toUInt32(213)) = [213,1,3,225,10001,10000]`.

### regionToName(id\[, lang\]) {#regiontonameid-lang}

Принимает число типа UInt32 - идентификатор региона из геобазы Яндекса. Вторым аргументом может быть передана строка - название языка. Поддерживаются языки ru, en, ua, uk, by, kz, tr. Если второй аргумент отсутствует - используется язык ru. Если язык не поддерживается - кидается исключение. Возвращает строку - название региона на соответствующем языке. Если региона с указанным идентификатором не существует - возвращается пустая строка.

`ua` и `uk` обозначают одно и то же - украинский язык.
