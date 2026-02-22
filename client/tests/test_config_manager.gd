extends GutTest

# Test ConfigManager security improvements
func before_each():
	# Clear config before each test
	ConfigManager.clear_all()

func test_save_username_only():
	ConfigManager.save_username("testuser")
	var username = ConfigManager.load_username()
	assert_eq(username, "testuser", "Should save and load username")

func test_save_token():
	var token = "test_token_12345"
	ConfigManager.save_token(token)
	var loaded_token = ConfigManager.load_token()
	assert_eq(loaded_token, token, "Should save and load token")

func test_no_password_storage():
	# Verify that passwords are NOT saved
	ConfigManager.save_username("testuser")
	var username = ConfigManager.load_username()
	assert_eq(username, "testuser", "Username should be saved")
	
	# Old deprecated method should not save password
	ConfigManager.save_credentials("testuser", "password123")
	var creds = ConfigManager.load_credentials()
	assert_false(creds.has("password"), "Password should NOT be saved")

func test_clear_all():
	ConfigManager.save_username("testuser")
	ConfigManager.save_token("test_token")
	ConfigManager.clear_all()
	
	assert_eq(ConfigManager.load_username(), "", "Username should be cleared")
	assert_eq(ConfigManager.load_token(), "", "Token should be cleared")
