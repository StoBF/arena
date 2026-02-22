# Localization System – Godot 4 GDScript

This project uses a **modular localization system** that lets users choose their language (English, Ukrainian, Polish) on the **login and registration** screens. All UI text updates when the language changes.

---

## 1. Overview

- **Autoload:** `Localization` (`autoload/Localization.gd`) loads JSON translation files and keeps the selected language.
- **Locale files:** `locales/en.json`, `locales/uk.json`, `locales/pl.json`.
- **Persistence:** The chosen locale is saved to `user://locale.cfg` and restored on next run.
- **Godot integration:** `TranslationServer.set_locale()` is updated when the language changes so both `Localization.t("key")` and `tr("key")` work.

---

## 2. Step-by-Step: How It Works

### Step 1: User selects language

On **Login** or **Register** screens, the user picks a language from the **OptionButton** (e.g. English / Ukrainian / Polish).

### Step 2: Changing the locale

When the selection changes, the script calls:

```gdscript
Localization.load_locale("uk")  # or "en", "pl"
```

This:

1. Loads `locales/uk.json` into `Localization.translations`
2. Sets `Localization.locale` to `"uk"`
3. Saves the choice to `user://locale.cfg`
4. Calls `TranslationServer.set_locale("uk")`
5. Emits the `locale_changed` signal

### Step 3: UI updates

Every screen that shows translatable text:

1. Connects to `Localization.locale_changed` in `_ready()`.
2. Implements a `_localize_ui()` function that sets all labels, buttons, placeholders, and option items from translation keys.
3. Calls `_localize_ui()` once in `_ready()` and again whenever `locale_changed` is emitted.

Example:

```gdscript
func _ready() -> void:
	_localize_ui()
	Localization.locale_changed.connect(_localize_ui)

func _localize_ui() -> void:
	login_button.text = Localization.t("login_button")
	username_field.placeholder_text = Localization.t("username")
	password_field.placeholder_text = Localization.t("password")
```

### Step 4: Getting translated text

- **In code:** use `Localization.t("key")` (works even before `TranslationServer` is set).
- **In scenes:** you can use `tr("key")` in the editor; at runtime the locale is synced from `Localization`, so `tr("key")` matches the current language.

---

## 3. Adding a New Language (e.g. German)

### 3.1 Add the locale file

Create `locales/de.json` with the same keys as in `en.json`:

```json
{
  "login": "Anmelden",
  "username": "Benutzername",
  "password": "Passwort",
  "language": "Sprache",
  "english": "Englisch",
  "polish": "Polnisch",
  "ukrainian": "Ukrainisch",
  "german": "Deutsch",
  "back": "Zurück",
  ...
}
```

Keep keys identical to other locale files; only values change.

### 3.2 Register the locale in code

In **`autoload/Localization.gd`**, add the new code to the constant:

```gdscript
const SUPPORTED_LOCALES = ["en", "pl", "uk", "de"]
```

### 3.3 Add translation for the new language name

In **every** locale file (`en.json`, `uk.json`, `pl.json`, and `de.json`), add a key for the new language label, e.g.:

- `"german": "German"` (en.json)
- `"german": "Німецька"` (uk.json)
- `"german": "Niemiecki"` (pl.json)
- `"german": "Deutsch"` (de.json)

### 3.4 Add the option to the language selector

In **LoginPanel.gd** and **RegisterPanel.gd**, update the constant and the option list:

```gdscript
const LOCALE_ORDER = ["en", "uk", "pl", "de"]

# In _setup_language_selector(), the display name can come from a key:
# e.g. "german" for "de"
```

When building the OptionButton items, add an entry for `"de"` with text `Localization.t("german")`, and in `_localize_ui()` set the new item text the same way you do for English/Ukrainian/Polish.

### 3.5 (Optional) Add to Godot’s translation list

In **Project → Project Settings → Internationalization → Locale → Translations**, add `res://locales/de.json` if you want `tr()` to use it as well. The in-game language is still driven by `Localization.load_locale()`.

---

## 4. Code Examples

### 4.1 Login screen – language selector and dynamic UI

```gdscript
const LOCALE_ORDER = ["en", "uk", "pl"]

func _ready() -> void:
	_setup_language_selector()
	_localize_ui()
	Localization.locale_changed.connect(_localize_ui)

func _setup_language_selector() -> void:
	language_option.clear()
	for code in LOCALE_ORDER:
		var name_key = "english" if code == "en" else "ukrainian" if code == "uk" else "polish"
		language_option.add_item(Localization.t(name_key), LOCALE_ORDER.find(code))
	language_option.selected = LOCALE_ORDER.find(Localization.locale)
	language_option.item_selected.connect(_on_language_selected)

func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LOCALE_ORDER.size():
		Localization.load_locale(LOCALE_ORDER[index])

func _localize_ui() -> void:
	sign_in_button.text = Localization.t("login_button")
	create_button.text = Localization.t("register_button")
	username_field.placeholder_text = Localization.t("username")
	password_field.placeholder_text = Localization.t("password")
	language_label.text = Localization.t("language")
	# Update option button item labels to current language
	language_option.set_item_text(0, Localization.t("english"))
	language_option.set_item_text(1, Localization.t("ukrainian"))
	language_option.set_item_text(2, Localization.t("polish"))
```

### 4.2 Error and success messages

Always use translation keys for messages:

```gdscript
UIUtils.show_error(Localization.t("login_failed"))
UIUtils.show_success(Localization.t("register_success"))
```

### 4.3 Placeholder with fallback

If a key might be missing (e.g. during development):

```gdscript
var text = Localization.t("remember_me")
remember_me_checkbox.text = text if text != "remember_me" else "Remember me"
```

---

## 5. File Layout

```
locales/
  en.json
  uk.json
  pl.json
  (de.json when added)

autoload/
  Localization.gd    # Singleton: load_locale(), t(), locale_changed

scripts/ui/
  LoginPanel.gd      # Language OptionButton + _localize_ui
  RegisterPanel.gd   # Language OptionButton + _localize_ui
  LocaleMenuPanel.gd # Settings → Language (from main menu)
```

---

## 6. Checklist for New Screens

When adding a new screen that should be localized:

1. Add an OptionButton (or reuse a shared language selector) if the screen must allow changing language.
2. In `_ready()`:
   - Call `_localize_ui()`.
   - Connect `Localization.locale_changed` to `_localize_ui`.
3. In `_localize_ui()`, set every label, button text, and placeholder with `Localization.t("key")`.
4. Add any new keys used by this screen to **all** locale JSON files (`en`, `uk`, `pl`, and any new language).

This keeps the implementation **clean, modular, and easy to extend** with more languages later.
