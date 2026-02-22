extends GutTest

# Test Localization singleton
func test_localization_singleton():
	var translation1 = Localization.t("login")
	var translation2 = Localization.t("login")
	assert_ne(translation1, "login", "Should return translation, not key")

func test_load_locale():
	Localization.load_locale("en")
	assert_eq(Localization.locale, "en", "Should set locale to en")
	
	Localization.load_locale("uk")
	assert_eq(Localization.locale, "uk", "Should set locale to uk")

func test_translation_keys():
	Localization.load_locale("en")
	var login_text = Localization.t("login")
	assert_eq(login_text, "Login", "Should translate login key")
	
	var heroes_text = Localization.t("heroes")
	assert_eq(heroes_text, "Heroes", "Should translate heroes key")

func test_missing_translation():
	Localization.load_locale("en")
	var missing = Localization.t("nonexistent_key_12345")
	assert_eq(missing, "nonexistent_key_12345", "Should return key if translation missing")
