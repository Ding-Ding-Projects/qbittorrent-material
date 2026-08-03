# CONTRACTS.md — The Single Authoritative Contract

**Status:** NORMATIVE. Every feature team MUST comply. Where this document and any
other doc disagree, **CONTRACTS.md wins** for cross-team interface questions;
`ENGINE_API.md` / `src/base/**.h` win for exact engine signatures;
`DESIGN_SYSTEM.md` wins for visual tokens. If you find a genuine gap, pick the
option most consistent with what is written here and note it in your return
`notes` — do **not** silently invent a divergent convention.

This file exists so ~20 independent teams produce mutually-consistent code without
talking to each other. Read it end-to-end before writing a single file.

- **Project root (WRITE here):** `C:/Users/cntow/Documents/GitHub/qbittorrent-material`
- **Reference (READ-ONLY):** `C:/Users/cntow/Documents/GitHub/qBittorrent`
- **Language/Toolchain:** Qt 6.7+, C++20, CMake ≥ 3.24, libtorrent-rasterbar 2.x.

---

## 0. Table of Contents

1. QML module & singletons
2. Internationalization (i18n) — `qsTr` + FunnyTranslator + `I18n`
3. Logging — `logging.h` categories + `Log` singleton + message handler
4. Theme API — colors, roles, Material wiring, tokens, icons
5. Components — the 22 reusable QML types (exact public API)
6. Engine contract — Session / Torrent / Preferences signatures & enums
7. Bridge conventions — models, roles, controllers, QFuture bridging
8. Naming / style — headers, guards, namespaces, clang-format

---

## 1. QML Module & Singletons

### 1.1 One module: `qBittorrent`

There is exactly **one** QML module for the whole application, URI **`qBittorrent`**.
Every QML file (screens, dialogs, components, singletons) and every C++ QML type
(`QML_ELEMENT`) belongs to it. Because they share one module, **types in the module
are referenced by name with no local import**. You never write
`import "../components"` or `import qBittorrent.Components`. Inside any `.qml` file
you may use `MaterialCard { … }`, `DataTable { … }`, `Theme.color(…)`,
`Session.torrents()`, etc. directly.

The only imports a QML file needs are the Qt modules it uses, e.g.:

```qml
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.platform as Platform   // OS file dialogs only
```

Do **not** put a version number on Qt imports (Qt 6 style).

### 1.2 `qt_add_qml_module` configuration (authoritative)

The single module is declared once in `src/quick/CMakeLists.txt`. Feature teams add
their files to the `QML_FILES` / `SOURCES` lists but **must not** create a second
`qt_add_qml_module`.

```cmake
qt_add_qml_module(qbittorrent
    URI qBittorrent
    VERSION 1.0
    NO_PLUGIN                       # statically linked into the app binary
    QML_FILES
        qml/Main.qml
        qml/theme/Theme.qml
        qml/theme/Typography.qml
        qml/theme/Spacing.qml
        qml/theme/Icons.qml
        qml/theme/StateColors.qml
        qml/components/MDIcon.qml
        qml/components/MaterialCard.qml
        # … every screen/dialog/component .qml …
    SOURCES
        # C++ QML_ELEMENT / QML_SINGLETON bridge types
        models/transferlistmodel.h  models/transferlistmodel.cpp
        controllers/transfercontroller.h controllers/transfercontroller.cpp
        # … etc …
    RESOURCES
        ../../resources/fonts/Roboto.ttf
        ../../resources/fonts/RobotoMono.ttf
        ../../resources/fonts/MaterialSymbolsOutlined.ttf
        ../../resources/i18n/cantonese.json
        ../../resources/icons/flags/**       # 369 flag SVGs
)
```

- `qmlcachegen` is enabled by default (do not disable).
- QML types are auto-registered from filenames: `MaterialCard.qml` → type
  `MaterialCard`. Filenames therefore **must** be PascalCase and match the type
  name teams reference in this doc **exactly**.
- Singletons require `pragma Singleton` at the top of the `.qml` file **and** a
  `qmldir`-equivalent registration — with `qt_add_qml_module` this is done by adding
  `QT_QML_SINGLETON_TYPE` to the file's source properties. The build team wires this;
  feature teams just add `pragma Singleton` (QML singletons) or `QML_SINGLETON`
  (C++ singletons).

### 1.3 The complete singleton list

Access all of these **by name, no import**. Two origins:

**QML singletons** (`pragma Singleton`, in `qml/theme/`):

| Singleton     | Purpose                                                              |
|---------------|---------------------------------------------------------------------|
| `Theme`       | Color resolution + Material wiring. `Theme.color(id)`, `Theme.stateColor(state)`, elevation tokens. Thin QML facade over C++ `ThemeManager`. |
| `Typography`  | Font tokens: `Typography.headlineSmall`, `.titleMedium`, `.bodyMedium`, `.labelLarge`, `.mono`, … (each returns a configured `font` group / helper). |
| `Spacing`     | Numeric spacing/radius/elevation tokens: `Spacing.xs`(4) `.sm`(8) `.md`(12) `.lg`(16) `.xl`(24) `.xxl`(32); `Spacing.radiusCard`(12) `.radiusDialog`(16) `.radiusChip`(8) `.radiusField`(4). |
| `Icons`       | Icon-id → Material Symbols codepoint string: `Icons.play_arrow`, `Icons.delete`, … (§4.5). |
| `StateColors` | Semantic state → color mapping used across the app: `StateColors.forState(state)`, `StateColors.success`, `.warning`, `.error`, `.info`, `.done`, `.muted`. Backed by `Theme`. |

**C++ singletons** (`QML_ELEMENT` + `QML_SINGLETON`, in `src/quick/`):

| Singleton              | Kind                | Purpose |
|------------------------|---------------------|---------|
| `I18n`                 | controller          | Language state + runtime retranslate (§2). |
| `Log`                  | controller          | QML-side logging entry point (§3). |
| `Session`              | engine facade proxy | The BitTorrent session (torrents, add/remove, stats). QML sees the same instance as `BitTorrent::Session::instance()`. |
| `Preferences`          | engine facade proxy | Typed settings get/set (§6.4). |
| `ThemeManager`         | theme backend       | Color scheme, tray style, named-color JSON override. `Theme` (QML) delegates here. |
| `TransferListModel`    | model               | Registered as a **singleton** instance so every view shares one model; the proxy/filters wrap it. |

**Controllers** are `QML_ELEMENT` singletons too (one shared instance each) unless a
screen legitimately needs a fresh instance (then it is a plain `QML_ELEMENT` and the
view instantiates it). The following are **singletons**:
`AppController`, `TransferController`, `PropertiesController`, `AddTorrentController`,
`OptionsController`, `SearchController`, `RSSController`, `ExecutionLogController`,
`StatisticsController`, `TorrentCreatorController`, `SpeedLimitController`,
`AddTorrentParamsController`, `DesktopIntegration`.

**Registration pattern for a C++ singleton** (all bridge singletons look like this):

```cpp
class TransferController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    static TransferController *create(QQmlEngine *, QJSEngine *); // returns the app-owned instance
    // …
};
```

Engine-owned singletons (`Session`, `Preferences`, `ThemeManager`) expose their
existing `instance()` and are bridged with a `create()` that returns
`BitTorrent::Session::instance()` (etc.), so QML and C++ share one object.

---

## 2. Internationalization (i18n)

### 2.1 The rule: `qsTr("English")` everywhere, English literal **is** the key

**Every** user-visible string in QML is wrapped in `qsTr("…")` with the **natural
English text** inside. In C++ user-visible strings use `QObject::tr("…")` /
`QCoreApplication::translate(...)`. There are **no** translation key strings, no
`t("delete_torrent")`, no ID catalogs in call sites. The English literal is the key.

```qml
Button { text: qsTr("Add Torrent") }
Label  { text: qsTr("%1 of %2 (%3)").arg(done).arg(total).arg(pct) }   // use arg(), not string concat
MenuItem { text: qsTr("Force Recheck") }
```

**Forbidden:** hard-coded non-English literals; building keys; concatenating
translated fragments (`qsTr("Down") + ": "` — instead use one `qsTr("%1")` with
placeholders). Disambiguation when the same English means two things:
`qsTr("Open", "context: file menu")`.

### 2.2 FunnyTranslator (custom `QTranslator`)

Translation is **not** driven by Qt `.ts`/`.qm` files. A single C++ class
`Utils::I18n::FunnyTranslator : public QTranslator` provides all three modes by
overriding `translate()`:

```cpp
namespace Utils::I18n {

class FunnyTranslator final : public QTranslator
{
    Q_OBJECT
public:
    enum class Mode { English, Cantonese, Bilingual };

    explicit FunnyTranslator(QObject *parent = nullptr);

    void setMode(Mode mode);                          // reloads nothing; just flips behavior
    bool loadCatalog(const QString &jsonPath);        // resources/i18n/cantonese.json
    bool isEmpty() const override { return false; }   // MUST return false so Qt calls translate()

    // Qt calls this for every qsTr()/tr(). `sourceText` is the English literal (the key).
    QString translate(const char *context, const char *sourceText,
                      const char *disambiguation, int n) const override;

private:
    QHash<QString, QString> m_enToYue;   // English literal -> Cantonese
    Mode m_mode = Mode::English;
};

} // namespace Utils::I18n
```

`translate()` semantics (normative):

- `English` → return empty `QString()` so Qt uses the original English literal.
- `Cantonese` → look up `sourceText` in `m_enToYue`; return the Cantonese if present,
  else fall back to the English `sourceText` (so untranslated strings still render).
- `Bilingual` → compose `English + " · " + Cantonese` when a Cantonese entry exists
  (thin separator `" · "`); otherwise return English alone. **Bilingual is composed
  at runtime — there is no third catalog.**

`resources/i18n/cantonese.json` is a flat English→Cantonese object; the Cantonese is
colloquial 港式口語 (real characters 嘅/係/喺/咗/唔/佢/嘢) with a cheeky HK tone:

```json
{
  "Pause": "唞下先",
  "Resume": "做返嘢",
  "Delete": "掟咗佢",
  "Force Recheck": "查家宅",
  "Add Torrent": "拉隻嘢入嚟",
  "Settings": "校下嘢"
}
```

### 2.3 The `I18n` singleton (QML-facing API)

```cpp
class I18n : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(Language language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString languageName READ languageName NOTIFY languageChanged)
public:
    enum Language { English = 0, Cantonese = 1, Bilingual = 2 };
    Q_ENUM(Language)

    static I18n *create(QQmlEngine *engine, QJSEngine *);

    Language language() const;
    QString  languageName() const;                 // localized display name for the current mode

    Q_INVOKABLE void setLanguage(Language lang);    // swaps translator mode + retranslates + persists
    Q_INVOKABLE QString t(const QString &english);  // programmatic translate (same result as qsTr)

signals:
    void languageChanged();

private:
    QQmlEngine *m_engine = nullptr;
    Utils::I18n::FunnyTranslator *m_translator = nullptr;  // installed on qApp
};
```

`setLanguage()` MUST (in order): log the change (`Log`/`lcI18n`); map the enum to
`FunnyTranslator::Mode` and call `m_translator->setMode(...)`; call
`m_engine->retranslate()` so **all live QML `qsTr` bindings re-evaluate with no
restart**; persist via `Preferences` under the key **`Appearance/Language`**
(stored as the integer enum value; default `English`); emit `languageChanged()`.
On startup `Application` reads `Appearance/Language`, constructs the translator,
installs it on `qApp`, and sets the initial mode **before** the QML engine loads
`Main.qml`.

Provide `t()` for the rare programmatic case (e.g., composing a model `displayValue`
in C++ — but prefer `QObject::tr` there). Never use `t("key")` with a non-English
key.

### 2.4 Usage example (QML)

```qml
// Options → Behavior: language selector
ComboBox {
    id: languageBox
    model: [ qsTr("English"), qsTr("Cantonese"), qsTr("Bilingual") ]
    currentIndex: I18n.language
    onActivated: (i) => {
        Log.info("i18n", "User changed language to index " + i)
        I18n.setLanguage(i)          // English=0, Cantonese=1, Bilingual=2
    }
}

// Any label just uses qsTr; it updates live when language changes:
Label { text: qsTr("Downloading") }
```

---

## 3. Logging — aggressive, dual-sink

### 3.1 C++ categories (`src/base/logging.h`)

`logging.h` declares one `Q_DECLARE_LOGGING_CATEGORY` per subsystem; the matching
`Q_LOGGING_CATEGORY` lives in `logging.cpp`. The full, fixed set (do not add ad-hoc
categories):

```cpp
// src/base/logging.h
#pragma once
#include <QLoggingCategory>

Q_DECLARE_LOGGING_CATEGORY(lcApp)      // "qbt.app"     application lifecycle
Q_DECLARE_LOGGING_CATEGORY(lcEngine)   // "qbt.engine"  libtorrent engine glue
Q_DECLARE_LOGGING_CATEGORY(lcSession)  // "qbt.session" BitTorrent::Session
Q_DECLARE_LOGGING_CATEGORY(lcTorrent)  // "qbt.torrent" per-torrent state
Q_DECLARE_LOGGING_CATEGORY(lcModel)    // "qbt.model"   bridge models
Q_DECLARE_LOGGING_CATEGORY(lcUi)       // "qbt.ui"      controllers / UI actions from C++
Q_DECLARE_LOGGING_CATEGORY(lcTheme)    // "qbt.theme"
Q_DECLARE_LOGGING_CATEGORY(lcI18n)     // "qbt.i18n"
Q_DECLARE_LOGGING_CATEGORY(lcNet)      // "qbt.net"
Q_DECLARE_LOGGING_CATEGORY(lcRss)      // "qbt.rss"
Q_DECLARE_LOGGING_CATEGORY(lcSearch)   // "qbt.search"
Q_DECLARE_LOGGING_CATEGORY(lcLog)      // "qbt.log"     the logging subsystem itself
```

**Usage (log aggressively — prefer too much over too little):**

```cpp
#include "base/logging.h"

qCDebug(lcSession) << "Adding torrent" << id << "savePath=" << params.savePath;
qCInfo(lcSession)  << "Torrent added" << torrent->name();
qCWarning(lcNet)   << "Proxy connect failed, retrying" << host << port;
qCCritical(lcTorrent) << "I/O error on" << torrent->name() << ':' << message;
```

Log **every**: lifecycle step (ctor/dtor/init/shutdown), state change, libtorrent
alert, error/warning with context, settings change, model reset/update. Non-trivial
functions emit at least an entry or action line at `qCDebug`.

Levels map: TRACE/DEBUG → `qCDebug`, INFO → `qCInfo`, WARNING → `qCWarning`,
CRITICAL → `qCCritical`. Default build enables DEBUG for all `qbt.*` categories;
threshold is raisable via `QT_LOGGING_RULES` / a Preferences setting.

### 3.2 The `Log` singleton (QML-facing)

```cpp
class Log : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    static Log *create(QQmlEngine *, QJSEngine *);

    Q_INVOKABLE void trace   (const QString &category, const QString &message);
    Q_INVOKABLE void debug   (const QString &category, const QString &message);
    Q_INVOKABLE void info    (const QString &category, const QString &message);
    Q_INVOKABLE void warning (const QString &category, const QString &message);
    Q_INVOKABLE void critical(const QString &category, const QString &message);
};
```

The `category` string is one of the short tags: `"app" "engine" "session" "torrent"
"model" "ui" "theme" "i18n" "net" "rss" "search" "log"`. `Log` maps the tag to the
matching `QLoggingCategory` and forwards to `qCDebug/…`, so QML logs flow through the
same sinks as C++.

**QML must log every user action and important state change:**

```qml
Button {
    text: qsTr("Delete")
    onClicked: {
        Log.info("ui", "Delete clicked for " + selection.count + " torrent(s)")
        confirmDelete.open()
    }
}

ConfirmDialog {
    onAccepted: { Log.info("ui", "Delete confirmed"); TransferController.deleteSelected(alsoFiles) }
    onRejected: Log.debug("ui", "Delete cancelled")
}

// selection / dialog lifecycle:
onCurrentTorrentChanged: Log.debug("ui", "Current torrent -> " + (torrent ? torrent.name : "none"))
Component.onCompleted:  Log.debug("ui", "OptionsDialog opened")
```

Log on: button clicks, menu actions, dialog open/accept/reject, selection changes,
tab switches, filter changes, and every meaningful state transition.

### 3.3 Dual sink & message handler

`Application` installs a `qInstallMessageHandler` that, for **every** Qt message:

1. formats `timestamp [category] [level] (threadId) message`;
2. writes to a **rotating log file** (`qbittorrent.log`, size-capped with N backups)
   under the app data dir; and
3. forwards to the engine `Logger` (`base/logger.h`), which feeds the in-app
   **Execution Log** screen via `ExecutionLogController`/`LogMessageModel`
   (ring buffer 20000). Peer-ban lines route to `LogPeerModel`.

Teams never call the handler directly — just use `qCDebug/…` (C++) or `Log.*` (QML)
and both sinks receive it.

---

## 4. Theme API

### 4.1 Color resolution

All color comes from `Theme` (QML) backed by `ThemeManager` (C++). **Never** hard-code
a hex color in a component; **never** use `Material.color(...)` palette enums for
semantic color.

```qml
color: Theme.color("primary")                 // Material role
color: Theme.color("onSurfaceVariant")        // role
color: Theme.color("StalledDownloading")      // named-id (transfer-list row state) -> resolves to role
color: Theme.stateColor(model.state)          // convenience: TorrentState int -> row text color
background.color: Theme.color("surface")
```

`Theme.color(id)` resolution order (matches `ThemeManager`): (1) user `config.json`
override table (`colors` / `colors.dark`); (2) named-id → role map (§ DESIGN_SYSTEM
tables — e.g. `StalledDownloading`→`successEmphasis`, `Log.Warning`→`severe`);
(3) the base Material role. It always returns a valid `color`.

Roles available (light/dark auto-selected by scheme): `primary primaryContainer
onPrimary onPrimaryContainer secondary tertiary surface surfaceVariant onSurface
onSurfaceVariant outline outlineVariant error onError` plus the qBittorrent
**extended roles**: `success successEmphasis warning done info muted severe`
(each with `on…`/`…Container` variants where defined in DESIGN_SYSTEM).

### 4.2 State colors

```qml
StateColors.forState(state)   // TorrentState int -> the row TEXT color (same as Theme.stateColor)
StateColors.success / .warning / .error / .info / .done / .muted
```

Row text color, progress-bar color, and state icon are **three independent channels**
gated by different prefs — never couple them. Progress bar uses `primary` unless
`GUI/TransferList/ProgressBarFollowsTextColor` is set, then it takes the row state
color. Row text uses the state color only when `…/UseTorrentStatesColors` is set.

### 4.3 Material attached-property wiring

`Main.qml` (the `ApplicationWindow`) sets the Material palette from `Theme` **once**,
at the root, so all stock controls inherit it. Individual components normally do
**not** set `Material.*` — they read `Theme`/`Spacing` directly. The root wiring:

```qml
ApplicationWindow {
    Material.theme: Theme.isDark ? Material.Dark : Material.Light
    Material.accent: Theme.color("primary")
    Material.primary: Theme.color("primary")
    Material.background: Theme.color("surface")
    Material.foreground: Theme.color("onSurface")
    // style forced to Material in C++: QQuickStyle::setStyle("Material")
}
```

Use `Material.elevation` only where a component's spec calls for a specific elevation
(cards, dialogs, menus) — pull the number from the tokens below.

### 4.4 Elevation & spacing tokens

Spacing/radius come from `Spacing` (§1.3). Elevation numbers (Material `elevation`):
page `0`; NavigationRail/Drawer `0` (+ outline); card/groupbox `1` (`2` when an
expandable CheckableGroupBox is expanded); toolbar `0` (+ bottom divider); Menu/popup
`8`; Snackbar `6`; Dialog `24`; FAB `6`. Expose as `Spacing.elevationCard` etc. if a
team needs them by name; otherwise use the literal from this list consistently.

### 4.5 Icons — `Icons.<name>` + `MDIcon`

`Icons` maps every legacy icon id to a **Material Symbols Outlined** codepoint
(a `\uXXXX` string). Render **only** via `MDIcon` (never a raw `Text` with the glyph):

```qml
MDIcon { icon: Icons.play_arrow }                       // start
MDIcon { icon: Icons.delete;   color: StateColors.error; size: 20 }
MDIcon { icon: Icons.settings; fill: true }
```

The authoritative id→symbol map is in DESIGN_SYSTEM §4 (e.g. add torrent `note_add`,
delete `delete`, start `play_arrow`, stop `pause`, force recheck `fact_check`,
options `settings`, category `category`, tags `sell`, …). Use those `Icons.<name>`
identifiers verbatim. Country flags are **not** Material — use
`Image { source: "image://flags/" + isoCode }` (the `FlagImageProvider`).

---

## 5. Components — the 22 reusable QML types

These live in `qml/components/` and are used **by name, no import**. Property and
signal names below are **binding contracts** — match them exactly. Every component
logs its own meaningful interactions via `Log` and pulls color/spacing from the
singletons.

### 5.1 `MDIcon`
Renders a Material Symbols glyph as text.
- **Properties:** `icon: string` (a codepoint from `Icons.*`, required);
  `size: int` (px, default 24); `color: color` (default `Theme.color("onSurface")`);
  `fill: bool` (default false — sets the `FILL` axis); `weight: int` (default 400).
- **Usage:** `MDIcon { icon: Icons.download; size: 20; color: StateColors.info }`

### 5.2 `IconButton`
Flat/round Material button wrapping an `MDIcon` with a tooltip.
- **Properties:** `icon: string`; `size: int` (icon size); `tooltip: string`
  (already `qsTr`'d by caller); `enabled`, `checkable`, `checked` (standard);
  `color: color`.
- **Signals:** `clicked()` (also `toggled(bool)` when `checkable`).
- **Usage:** `IconButton { icon: Icons.refresh; tooltip: qsTr("Refresh"); onClicked: … }`

### 5.3 `MaterialCard`
Elevated rounded container (radius `Spacing.radiusCard`, elevation 1). Default
property is its content.
- **Properties:** `title: string` (optional header via `SectionHeader`);
  `padding: int` (default `Spacing.md`); `elevation: int` (default 1);
  `contentItem`/default children.
- **Usage:** `MaterialCard { title: qsTr("Transfer"); ColumnLayout { … } }`

### 5.4 `SectionHeader`
Card/section title row (titleMedium, optional trailing slot).
- **Properties:** `text: string`; `icon: string` (optional leading `Icons.*`);
  default property `trailing` (right-aligned controls).

### 5.5 `CollapsibleSection`
Expand/collapse container with an animated header chevron.
- **Properties:** `title: string`; `expanded: bool` (default true);
  `icon: string` (optional); default children = body.
- **Signals:** `toggled(bool expanded)`.
- Persists `expanded` when given a `persistKey: string`.

### 5.6 `CheckableGroupBox`
Group box whose header `Switch` enables/disables (and expands) the body; elevation
1→2 on expand.
- **Properties:** `title: string`; `checked: bool` (two-way; the switch state);
  default children = body (disabled when `!checked`).
- **Signals:** `toggled(bool checked)`.
- **Usage:** `CheckableGroupBox { title: qsTr("Email notification"); checked: … ; … }`

### 5.7 `LabeledField`
A left/top label paired with an arbitrary control (form row).
- **Properties:** `label: string`; `control: Item` (the editor; may also be given as
  the default child); `labelWidth: int` (optional, for column alignment);
  `orientation` (row/column, responsive).
- **Usage:** `LabeledField { label: qsTr("Save path"); control: PathField { … } }`

### 5.8 `PathField`
Text field + trailing folder/file picker button (OS dialog via `Qt.labs.platform`).
- **Properties:** `path: string` (two-way); `pickFolder: bool` (default true — folder
  vs file picker); `placeholder: string`; `title: string` (dialog caption, `qsTr`'d).
- **Signals:** `pathChanged(string path)` (via property NOTIFY); `accepted()`.

### 5.9 `PathComboField`
Like `PathField` but the editor is an editable `ComboBox` of recent/known paths.
- **Properties:** `path: string` (two-way, = current text); `model` (path list);
  `pickFolder: bool`; `placeholder: string`.
- **Signals:** `pathChanged`.

### 5.10 `SpeedSpinBox`
Numeric spin box for KiB/s limits with sentinel text.
- **Properties:** `value: int` (KiB/s; `0` or `-1` per context = special);
  `from`, `to`, `stepSize`; `unlimitedText: string` (shown for the unlimited
  sentinel, e.g. `qsTr("∞")`); `suffix: string` (e.g. `qsTr("KiB/s")`).
- Renders sentinels via `textFromValue` (∞ / 0 disabled / Never / system default).

### 5.11 `TriStateComboField`
Three-way Default / Yes / No selector mapping to an optional bool.
- **Properties:** `value` — a tri-state token: `TriStateComboField.Default`,
  `.Yes`, `.No` (an `enum`; `Default` == "use global/unset"). Two-way bindable.
- **Signals:** `valueChanged(int value)`. C++ side maps to `std::optional<bool>`.
- **Usage:** `TriStateComboField { value: params.addToTopOfQueue }`

### 5.12 `FilterTextField`
Search/filter input with a clear affordance and a regex toggle.
- **Properties:** `text: string` (two-way); `placeholder: string`;
  `regexEnabled: bool` (two-way; toggled from the embedded `FilterPatternFormatMenu`).
- **Signals:** `textChanged`, `regexEnabledChanged`.

### 5.13 `FilterPatternFormatMenu`
Context menu offering the pattern format (Wildcard / Regex / plain) for a
`FilterTextField`.
- **Properties:** `regexEnabled: bool` (two-way).
- **Signals:** `formatChanged`. Opened via `popup()`.

### 5.14 `DataTable`
The core table: wraps `HorizontalHeaderView` + `TableView`, with movable first
section, per-column alignment, sort indicator, header menu, persisted state.
- **Properties:**
  - `model` — a `QAbstractItemModel` (usually a sort/filter proxy).
  - `columns: list` — column descriptors: `[{ role, title, width, align, visible,
    resizable }]` (`title` already `qsTr`'d by the caller; `role` matches the model
    role name).
  - `delegateFor: function(column) -> Component` — returns the cell delegate for a
    column (lets callers plug `ProgressCell`, combo delegates, checkbox+icon name
    cells). Default returns a plain text cell.
  - `persistKey: string` — header state (order/width/visibility/sort) persistence id.
  - `selectionModel` / `currentRow` — selection state exposed to the view.
- **Signals:** `activated(int row)` (double-click / Enter), `contextRequested(int
  row, point pos)`, `selectionChanged()`.
- Header right-click opens `ColumnHeaderMenu`.

### 5.15 `ColumnHeaderMenu`
Checkable column-visibility menu + "Resize columns", with last-visible-column guard.
- **Properties:** `columns` (the same descriptor list, bound two-way for `visible`).
- **Signals:** `resizeRequested()`, `visibilityChanged(role, bool)`.

### 5.16 `ProgressCell`
Progress bar with a centered `%` label; disabled look for Error/Stopped/Unknown.
- **Properties:** `progress: real` (0.0–1.0); `active: bool` (default true —
  `enabled:false` styling when false); `text: string` (optional override, default
  computed `%`).
- Color per §4.2 (primary or follows row text color).

### 5.17 `Snackbar`
Transient bottom notification (elevation 6). Singleton-ish per window; used when a tab
is unfocused.
- **API:** `Snackbar.show(text)` — imperative; `text` already `qsTr`'d. Optional
  `Snackbar.show(text, actionText, callback)`.
- One `Snackbar` instance lives in `Main.qml`; teams call `Snackbar.show(...)`.

### 5.18 `ConfirmDialog`
Material confirmation dialog with optional "don't ask again".
- **Properties:** `title: string`; `text: string`; `acceptText: string`
  (default `qsTr("OK")`); `rejectText: string` (default `qsTr("Cancel")`);
  `destructive: bool` (shows a warning `MDIcon`); `rememberKey: string` (when set,
  shows a "Don't ask again" checkbox persisted to that Preferences key — if remembered
  `true`, `open()` auto-accepts).
- **Signals / handlers:** `onAccepted`, `onRejected`. Call `open()`.
- **Usage:**
  ```qml
  ConfirmDialog {
      id: del
      title: qsTr("Remove torrent?")
      text: qsTr("Also delete the downloaded files?")
      destructive: true
      rememberKey: "Confirm/DeleteTorrent"
      onAccepted: TransferController.deleteSelected(alsoFiles.checked)
  }
  ```

### 5.19 `TextInputDialog`
One-line prompt (rename, add tag, new category, URL, …).
- **Properties:** `title: string`; `label: string`; `text: string` (initial/edited
  value, two-way); `placeholder: string`; `validator` (optional).
- **Signals / handlers:** `onAccepted(string text)`, `onRejected`. Call `open()`.
- **Usage:** `TextInputDialog { title: qsTr("Rename"); label: qsTr("New name"); text: torrent.name; onAccepted: (t) => TransferController.rename(t) }`

### 5.20 `SharedShareLimitsForm`
Reusable ratio/seeding-time share-limit editor (used by Torrent Options, category,
Add-torrent, RSS rules).
- **Properties:** `ratioLimit: real` (`-1` global, `-2` none/unlimited per engine
  convention); `seedingTimeLimit: int` (minutes); `inactiveSeedingTimeLimit: int`;
  `onLimitReached` (action enum). Two-way bindable; mirrors `BitTorrent::ShareLimits`.
- **Signals:** `changed()`.

### 5.21 `AddTorrentParamsForm`
Reusable default add-torrent parameters editor (save path, category, tags, AutoTMM,
start/skip-hash, content layout, …). Backed by `AddTorrentParamsController`.
- **Properties:** `params` — an `AddTorrentParams`-shaped object/gadget (two-way);
  uses `TriStateComboField` for optional bools; `PathComboField` for save path.
- **Signals:** `changed()`. Reused by RSS auto-download rules, category dialog, and
  watched folders per ARCHITECTURE.

### 5.22 `LabeledSwitch` / misc small field wrappers
(Completing the 22.) `LabeledSwitch` — a `LabeledField` specialized for a `Switch`.
- **Properties:** `label: string`; `checked: bool` (two-way); `description: string`
  (optional helper line, labelSmall/muted).
- **Signals:** `toggled(bool)`.

> If a screen needs a field wrapper not listed, compose from `LabeledField` +
> a Material control rather than inventing a new global component.

---

## 6. Engine Contract

The engine under `src/base` preserves qBittorrent's class/method names, persisted
setting keys, and **enum numeric values** for config compatibility. **`src/base/**.h`
and `ENGINE_API.md` are the source of truth**; engine teams generate those headers.
Bridge/UI teams code against the signatures below and `#include` the real headers.

### 6.1 `BitTorrent::Session`

Singleton facade over the libtorrent session (runs on a dedicated IO thread).

```cpp
namespace BitTorrent {
class Session : public QObject
{
    Q_OBJECT
public:
    static Session *instance();                       // the one facade
    QList<Torrent *> torrents() const;
    Torrent *getTorrent(const TorrentID &id) const;
    qsizetype torrentsCount() const;

    bool addTorrent(const TorrentDescriptor &source, const AddTorrentParams &params = {});
    bool removeTorrent(const TorrentID &id, DeleteOption option = DeleteOption::KeepFiles);
    // start/stop/recheck/reannounce/queue moves/setCategory/setTags/setLocation/…
    // (see session.h — one method per transfer-list action)

    SessionStatus status() const;                     // aggregate stats (speeds, totals)
    CacheStatus   cacheStatus() const;

signals:
    void torrentsLoaded(const QList<Torrent *> &torrents);
    void torrentsUpdated(const QList<Torrent *> &torrents);   // periodic bulk update — models react to THIS
    void statsUpdated();                                       // session-wide stats tick
    void torrentAdded(Torrent *torrent);
    void torrentAboutToBeRemoved(Torrent *torrent);
    void torrentFinished(Torrent *torrent);
    void torrentMetadataReceived(Torrent *torrent);
    void torrentCategoryChanged(Torrent *torrent, const QString &oldCategory);
    void torrentTagAdded(Torrent *torrent, const Tag &tag);
    void torrentTagRemoved(Torrent *torrent, const Tag &tag);
    // … (full set in session.h)
};
} // namespace BitTorrent
```

**Models subscribe to these signals; they never poll.** `torrentsUpdated` and
`statsUpdated` drive the transfer list and speed plots respectively.

### 6.2 `BitTorrent::Torrent` (getters used by the bridge)

`Torrent` is an abstract QObject-free interface (getters used to build model roles):
`id()`, `name()`, `state()` (→ `TorrentState`), `progress()`, `downloadPayloadRate()`,
`uploadPayloadRate()`, `totalSize()`, `wantedSize()`, `completedSize()`, `eta()`,
`ratio()`, `category()`, `tags()`, `savePath()`, `addedTime()`, `completedTime()`,
`seedsCount()/leechesCount()/totalSeedsCount()/totalLeechesCount()`,
`connectionsCount()`, `isStopped()/isQueued()/isForced()/isChecking()/isDownloading()/
isUploading()/isMoving()/isErrored()/hasMissingFiles()/hasMetadata()`, `error()`.
Async detail reads return `QFuture<T>`:
`fetchPeerInfo()`, `fetchURLSeeds()`, `fetchPieceAvailability()`,
`fetchDownloadingPieces()`, `fetchAvailableFileFractions()`.

### 6.3 `BitTorrent::TorrentState` (numeric values — **stable, do not renumber**)

```cpp
enum class TorrentState
{
    Unknown = -1,
    ForcedDownloading = 0,
    Downloading,                // 1
    ForcedDownloadingMetadata,  // 2
    DownloadingMetadata,        // 3
    StalledDownloading,         // 4
    ForcedUploading,            // 5
    Uploading,                  // 6
    StalledUploading,           // 7
    CheckingResumeData,         // 8
    QueuedDownloading,          // 9
    QueuedUploading,            // 10
    CheckingUploading,          // 11
    CheckingDownloading,        // 12
    StoppedDownloading,         // 13
    StoppedUploading,           // 14
    Moving,                     // 15
    MissingFiles,               // 16
    Error                       // 17
};
```

QML receives `state` as the **int**; map to colors via `StateColors.forState(state)` /
`Theme.stateColor(state)` and to icons via the DESIGN_SYSTEM status map. Expose the
enum to QML by registering it (`Q_ENUM` on a wrapper or
`qmlRegisterUncreatableMetaObject`) so QML can name values if needed.

### 6.4 `Preferences`

```cpp
class Preferences : public QObject
{
    Q_OBJECT
public:
    static Preferences *instance();
    // typed getters/setters, one pair per setting, e.g.:
    QString getSavePath() const;               void setSavePath(const QString &);
    int     getGlobalDownloadLimit() const;    void setGlobalDownloadLimit(int);
    // generic access for bridge convenience:
    QVariant value(const QString &key, const QVariant &def = {}) const;
    void     setValue(const QString &key, const QVariant &value);
    void     apply();
signals:
    void changed();
};
```

**Setting keys are preserved verbatim** from legacy qBittorrent (Qt6-namespaced only
where unavoidable) so existing configs load. New keys introduced by this rewrite:
`Appearance/Language` (int, §2.3). Read/write through `Preferences`; never touch
`QSettings` directly from a feature.

### 6.5 Other engine facades

`RSS::Session`, `Search::SearchPluginManager`/`SearchHandler`, `Net::DownloadManager`,
`TorrentCreator`, `Logger` — signatures in their respective `src/base/**` headers /
`ENGINE_API.md`. Same rule: subscribe to signals, call `Q_INVOKABLE`-friendly methods
from controllers, never poll.

---

## 7. Bridge Conventions

### 7.1 Model role naming

List/table models use **named roles via `roleNames()`**, one role per column plus two
underlying-data roles. Names are lowerCamelCase and are what `DataTable` `columns[].role`
references and what QML delegates read as `model.<role>`.

```cpp
enum Roles {
    NameRole = Qt::UserRole + 1,   // "name"
    SizeRole,                      // "size"
    ProgressRole,                  // "progress"
    StatusRole,                    // "status"   (TorrentState int)
    DownSpeedRole, UpSpeedRole, EtaRole, RatioRole, CategoryRole, TagsRole,
    AddedOnRole, SavePathRole, /* … one per visible column … */
    UnderlyingRole,                // "underlying"           raw value for sorting/formatting
    AdditionalUnderlyingRole       // "additionalUnderlying" secondary sort key
};
QHash<int, QByteArray> roleNames() const override; // maps each to its string name above
```

- `data()` returns the **display value** (already formatted & `tr`'d — e.g. speed
  "1.2 MiB/s", "∞", hidden-zero) for the primary role; the `Underlying*` roles return
  raw numeric values so the proxy can sort with natural compare.
- Transfer-list model additionally exposes the state color/icon via
  `StateColors`/DESIGN_SYSTEM mapping — but **prefer** returning the raw `status` int
  and letting QML resolve color (keeps color policy in one place).

### 7.2 Controller `Q_INVOKABLE` naming

Controllers expose `Q_INVOKABLE` verbs named after the user action, camelCase,
present-tense: `start()`, `stop()`, `forceStart()`, `forceRecheck()`,
`deleteSelected(bool deleteFiles)`, `setCategory(QString)`, `addTags(QStringList)`,
`moveUp()/moveDown()/moveTop()/moveBottom()`, `setLocation(QString)`,
`copyName()/copyHash()/copyMagnet()`, `rename(QString)`. State they publish is a
`Q_PROPERTY` with `NOTIFY`. Selection is passed in or held as a `Q_PROPERTY`
(`selectedIds`), not rediscovered per call.

The transfer-list export bridge follows the same rule: `exportFormats()` returns
format metadata (`token`, display name, extension, and pre-save loss note), and
`exportTransfers(formatToken, filePath, selectedOnly)` writes the current
selection or the full session. It returns an empty string on success and a
translated failure message otherwise; the controller owns escaping and atomic
file commit, while QML owns scope disclosure and the native Save-file picker.

### 7.3 `QFuture` → property bridging

Engine async reads (`QFuture<T>`) are bridged into notifiable properties with
`QFutureWatcher`, never blocked on:

```cpp
void PeerListModel::refresh()
{
    auto *w = new QFutureWatcher<QList<PeerInfo>>(this);
    connect(w, &QFutureWatcherBase::finished, this, [this, w] {
        applyPeers(w->result());          // update model -> dataChanged
        w->deleteLater();
        qCDebug(lcModel) << "Peer list refreshed:" << rowCount() << "peers";
    });
    w->setFuture(m_torrent->fetchPeerInfo());
}
```

Refresh is triggered by `torrentsUpdated` (per-tab, only for the current torrent) —
not by a timer.

---

## 8. Naming / Style

### 8.1 File header (every C++ and QML source)

Every file starts with the GPLv3 header block (SPDX form acceptable):

```cpp
/*
 * qBittorrent (Material rewrite) — a BitTorrent client
 * Copyright (C) 2026  qBittorrent-Material contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
```

### 8.2 Include guards & includes
- **`#pragma once`** in every header (no `#ifndef` guards).
- Include order: corresponding header, C/C++ stdlib, Qt, libtorrent, project — each
  group alphabetized, blank-line separated. Prefer forward declarations in headers.

### 8.3 Namespaces
- Engine: `BitTorrent`, `RSS`, `Search`, `Net`, `Utils` (`Utils::Fs::Path`,
  `Utils::String`, `Utils::Misc`, `Utils::IO`, `Utils::Version`, `Utils::I18n`).
- Bridge/QML types: either the **global namespace** or a small `namespace qbt`, but
  **must** carry `QML_ELEMENT`/`QML_SINGLETON` so they land in the `qBittorrent`
  module. Do not nest bridge types in the engine namespaces.

### 8.4 C++ language rules
- **C++20**, Qt 6. Use `Q_OBJECT`, `Q_PROPERTY`(with `MEMBER`/`READ`/`WRITE`/`NOTIFY`),
  `Q_INVOKABLE`, `Q_ENUM`. Prefer `enum class`. Use `nullptr`, `override`, `final`,
  `[[nodiscard]]`, `auto` where it aids clarity, structured bindings, `std::optional`
  for tri-state. Avoid raw owning pointers — parent QObjects or `std::unique_ptr`.
- Doxygen-lite comments: a one-line `///` or `/** */` on each public class and
  non-obvious method. No dead code, no `TODO` except the explicitly-allowed
  engine-deep libtorrent glue (mark `// TODO(engine): …`).

### 8.5 QML style
- PascalCase filenames/types; lowerCamelCase ids and properties. One component per
  file. `qsTr` on every visible string. No inline magic colors/sizes — use
  `Theme`/`Spacing`/`Typography`. Bind, don't poll. Log user actions via `Log`.

### 8.6 `.clang-format`
Format all C++ with the repo-root `.clang-format` (mirrors upstream qBittorrent:
Allman-ish braces, 4-space indent, 100-col soft limit, pointer-left `Type *name`,
east-const off). Run before committing.

---

## 9. Compliance Checklist (per file, before you finish)

- [ ] GPLv3 header present; `#pragma once` in headers.
- [ ] Every visible string wrapped in `qsTr("English")` / `tr(...)`; no keys.
- [ ] Colors via `Theme.color`/`StateColors`; spacing via `Spacing`; icons via `MDIcon`+`Icons`.
- [ ] Only Material controls + the 22 named Components; no Widgets, no native dialogs (except OS file pickers).
- [ ] Types referenced by name (single `qBittorrent` module); no local component imports.
- [ ] Models subscribe to engine signals (no polling); roles via `roleNames()`.
- [ ] Aggressive logging: C++ `qC*`, QML `Log.*` on every action/state change.
- [ ] Singletons accessed by the exact names in §1.3.
- [ ] Matches engine signatures/enums in `src/base/**.h` / `ENGINE_API.md`.
