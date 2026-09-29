# Шрифты интерфейса

`Nunito.ttf` — локальная копия вариативного шрифта Nunito из [Google Fonts](https://github.com/google/fonts/tree/main/ofl/nunito). В меню используется вес 600 для основного текста и 900 для заголовков и кнопок.

Авторство: Copyright 2014 The Nunito Project Authors ([проект шрифта](https://github.com/googlefonts/nunito)). Лицензия SIL Open Font License 1.1 сохранена рядом в [OFL.txt](OFL.txt). Файл шрифта включён в проект; подключение к сети для его загрузки во время игры не требуется.

`interface_font.tres` сохраняет Nunito основным шрифтом с весом 600 и дополняет отсутствующие в нём письменности локальными Noto. Явный вес нужен для читаемости: исходный вариативный Nunito имеет вес 200 по умолчанию. `interface_theme.tres` задаёт этот ресурс всему интерфейсу, включая всплывающие меню. Все файлы ниже — неизменённые оригиналы; у вариативных TTF упрощено только имя файла на диске.

| Файл | Назначение | Источник | Лицензия |
| --- | --- | --- | --- |
| `NotoSansArabicUI.ttf` | Арабский и урду; компактные метрики интерфейса | [Google Fonts, Noto Sans Arabic UI](https://github.com/google/fonts/tree/23e54b51ddffbc7713c583748e3bd86f62b1fa4a/ofl/notosansarabicui) | [SIL OFL 1.1](NotoSansArabicUI-OFL.txt) |
| `NotoSansBengali.ttf` | Бенгальский | [Google Fonts, Noto Sans Bengali](https://github.com/google/fonts/tree/23e54b51ddffbc7713c583748e3bd86f62b1fa4a/ofl/notosansbengali) | [SIL OFL 1.1](NotoSansBengali-OFL.txt) |
| `NotoSansDevanagari.ttf` | Хинди | [Google Fonts, Noto Sans Devanagari](https://github.com/google/fonts/tree/23e54b51ddffbc7713c583748e3bd86f62b1fa4a/ofl/notosansdevanagari) | [SIL OFL 1.1](NotoSansDevanagari-OFL.txt) |
| `NotoSansCJKsc-Regular.otf` | Китайские иероглифы, японская кана и кандзи | [Noto CJK, Sans/OTF/SimplifiedChinese](https://github.com/notofonts/noto-cjk/tree/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/OTF/SimplifiedChinese) | [SIL OFL 1.1](NotoSansCJK-OFL.txt) |

Авторство Noto Sans Arabic UI: Copyright 2012 Google Inc. All Rights Reserved. Авторство Noto Sans Bengali и Devanagari: Copyright 2022 The Noto Project Authors; проекты [Arabic](https://github.com/notofonts/arabic), [Bengali](https://github.com/notofonts/bengali) и [Devanagari](https://github.com/notofonts/devanagari). Noto CJK — проект [Noto Fonts](https://github.com/notofonts/noto-cjk), выполненный совместно с Adobe; сведения об авторстве также встроены в файл шрифта.

Добавленные Noto занимают около 17.6 MiB. Вариант Arabic UI сохраняет компактную высоту строк: метрики обычного Noto Sans Arabic увеличивают даже русские строки всей цепочки fallback. Один полный CJK-шрифт содержит китайские и японские символы и языковые варианты OpenType; Godot передаёт текущую локаль при формировании текста. Стандартный TextServer Godot выполняет соединение арабских букв, индийские лигатуры и двунаправленный текст. Шрифты не загружаются из сети и не требуют установки в ОС.
