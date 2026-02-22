extends GutTest

# Test ServerConfig singleton
func test_server_config_singleton():
	var config1 = ServerConfig.get_instance()
	var config2 = ServerConfig.get_instance()
	assert_eq(config1, config2, "Should return same instance")

func test_http_base_url():
	var config = ServerConfig.get_instance()
	config.server_ip = "localhost"
	config.http_port = 8000
	config.use_https = false
	
	var url = config.get_http_base_url()
	assert_eq(url, "http://localhost:8000", "Should generate correct HTTP URL")

func test_https_base_url():
	var config = ServerConfig.get_instance()
	config.server_ip = "example.com"
	config.http_port = 443
	config.use_https = true
	
	var url = config.get_http_base_url()
	assert_eq(url, "https://example.com:443", "Should generate correct HTTPS URL")

func test_ws_endpoint():
	var config = ServerConfig.get_instance()
	config.server_ip = "localhost"
	config.ws_port = 8000
	config.use_https = false
	
	var endpoint = config.get_ws_endpoint("general", "test_token")
	assert_eq(endpoint, "ws://localhost:8000/ws/general?token=test_token", "Should generate correct WebSocket endpoint")
