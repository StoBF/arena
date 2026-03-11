extends GutTest

# Test LocalizationManager singleton
func test_localization_manager_singleton():
	LocalizationManager.set_locale("en")
	var translation1 = tr("ui.common.login")
	var translation2 = tr("ui.common.login")
	assert_eq(translation1, translation2, "Should return deterministic translation")
	assert_ne(translation1, "ui.common.login", "Should return translation, not key")

func test_load_locale():
	LocalizationManager.set_locale("en")
	assert_eq(LocalizationManager.get_locale(), "en", "Should set locale to en")
	
	LocalizationManager.set_locale("uk")
	assert_eq(LocalizationManager.get_locale(), "uk", "Should set locale to uk")

func test_translation_keys():
	LocalizationManager.set_locale("en")
	var login_text = tr("ui.common.login")
	assert_eq(login_text, "Login", "Should translate login key")

	var storage_text = tr("ui.playerhub.storage")
	assert_eq(storage_text, "Storage", "Should translate storage key")

func test_missing_translation():
	LocalizationManager.set_locale("en")
	var missing = tr("nonexistent_key_12345")
	assert_eq(missing, "nonexistent_key_12345", "Should return key if translation missing")
