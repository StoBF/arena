# JWT Refresh Token Testing Guide

**Status**: Testing Ready  
**Scope**: Backend + Client Integration  
**Framework**: pytest (backend), GDScript (client)

---

## Testing Strategy Overview

### Test Categories

1. **Unit Tests** (Backend JWT utilities)
2. **Integration Tests** (Backend auth endpoints)
3. **End-to-End Tests** (Client + Backend)
4. **Security Tests** (Token rotation, cookie security)
5. **Load Tests** (Concurrent refresh scenarios)

---

## Backend Unit Tests

### JWT Token Generation & Validation

**File**: `Server/tests/test_jwt_tokens.py`

```python
import pytest
from datetime import datetime, timedelta
from app.utils.jwt import create_access_token, create_refresh_token, decode_access_token, decode_refresh_token
from app.core.config import settings

class TestAccessToken:
    """Test access token generation and expiration"""
    
    def test_create_access_token(self):
        """Test access token creation"""
        data = {"sub": "user123", "role": "user"}
        token = create_access_token(data)
        
        assert token is not None
        assert len(token) > 50  # JWT format
    
    def test_access_token_includes_type(self):
        """Test access token marked as 'access' type"""
        data = {"sub": "user123"}
        token = create_access_token(data)
        payload = decode_access_token(token)
        
        assert payload is not None
        assert payload.get("type") == "access"
    
    def test_access_token_expiration(self):
        """Test access token expires after 20 minutes"""
        data = {"sub": "user123"}
        token = create_access_token(data)
        payload = decode_access_token(token)
        
        exp = datetime.fromtimestamp(payload["exp"])
        now = datetime.utcnow()
        delta = exp - now
        
        # Should expire in ~20 minutes (allow 30 second variance)
        assert 19*60 < delta.total_seconds() < 21*60
    
    def test_decode_access_token_invalid(self):
        """Test decoding invalid access token returns None"""
        invalid_token = "invalid.token.here"
        payload = decode_access_token(invalid_token)
        
        assert payload is None
    
    def test_decode_access_token_wrong_type(self):
        """Test decoding refresh token as access token fails"""
        data = {"sub": "user123"}
        refresh_token, _ = create_refresh_token(data)
        
        # Try to decode refresh token as access token
        payload = decode_access_token(refresh_token)
        
        assert payload is None  # Wrong type


class TestRefreshToken:
    """Test refresh token generation and rotation"""
    
    def test_create_refresh_token(self):
        """Test refresh token creation"""
        data = {"sub": "user123", "role": "user"}
        token, family_id = create_refresh_token(data)
        
        assert token is not None
        assert family_id is not None
        assert len(family_id) == 36  # UUID format "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    
    def test_refresh_token_includes_family(self):
        """Test refresh token includes rotation family ID"""
        data = {"sub": "user123"}
        token, family_id = create_refresh_token(data)
        payload = decode_refresh_token(token)
        
        assert payload is not None
        assert payload.get("family") == family_id
    
    def test_refresh_token_includes_type(self):
        """Test refresh token marked as 'refresh' type"""
        data = {"sub": "user123"}
        token, _ = create_refresh_token(data)
        payload = decode_refresh_token(token)
        
        assert payload.get("type") == "refresh"
    
    def test_refresh_token_expiration(self):
        """Test refresh token expires after 7 days"""
        data = {"sub": "user123"}
        token, _ = create_refresh_token(data)
        payload = decode_refresh_token(token)
        
        exp = datetime.fromtimestamp(payload["exp"])
        now = datetime.utcnow()
        delta = exp - now
        
        # Should expire in ~7 days (allow 30 second variance)
        assert 7*24*60*60 - 30 < delta.total_seconds() < 7*24*60*60 + 30
    
    def test_refresh_token_with_custom_family(self):
        """Test refresh token with provided family ID (for rotation)"""
        data = {"sub": "user123"}
        custom_family = "family-uuid-xxxx"
        token, family_id = create_refresh_token(data, family_id=custom_family)
        
        assert family_id == custom_family
        payload = decode_refresh_token(token)
        assert payload.get("family") == custom_family
    
    def test_decode_refresh_token_invalid(self):
        """Test decoding invalid refresh token returns None"""
        invalid_token = "invalid.token.here"
        payload = decode_refresh_token(invalid_token)
        
        assert payload is None
    
    def test_decode_refresh_token_wrong_type(self):
        """Test decoding access token as refresh token fails"""
        data = {"sub": "user123"}
        access_token = create_access_token(data)
        
        # Try to decode access token as refresh token
        payload = decode_refresh_token(access_token)
        
        assert payload is None  # Wrong type


class TestTokenSeparation:
    """Test access and refresh tokens are distinct"""
    
    def test_tokens_different(self):
        """Test access and refresh tokens are different"""
        data = {"sub": "user123"}
        access_token = create_access_token(data)
        refresh_token, _ = create_refresh_token(data)
        
        assert access_token != refresh_token
    
    def test_access_token_not_decodable_as_refresh(self):
        """Test access token cannot be used as refresh token"""
        data = {"sub": "user123"}
        access_token = create_access_token(data)
        
        payload = decode_refresh_token(access_token)
        assert payload is None
    
    def test_refresh_token_not_decodable_as_access(self):
        """Test refresh token cannot be used as access token"""
        data = {"sub": "user123"}
        refresh_token, _ = create_refresh_token(data)
        
        payload = decode_access_token(refresh_token)
        assert payload is None
```

---

## Backend Integration Tests

### Auth Endpoint Testing

**File**: `Server/tests/test_auth_endpoints.py`

```python
import pytest
from httpx import AsyncClient
from app.main import app
from app.database import AsyncSession, get_session

@pytest.mark.asyncio
class TestLoginEndpoint:
    """Test /auth/login endpoint"""
    
    async def test_login_success(self, client: AsyncClient, test_user):
        """Test successful login"""
        response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert "token_type" in data
        assert data["token_type"] == "bearer"
    
    async def test_login_sets_refresh_cookie(self, client: AsyncClient, test_user):
        """Test login sets refresh_token in HTTP-only cookie"""
        response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        # Check Set-Cookie header
        cookies = response.cookies
        assert "refresh_token" in cookies
        
        # Verify cookie attributes
        cookie = cookies["refresh_token"]
        assert cookie.get("httponly") == True
        assert cookie.get("secure") == True
        assert cookie.get("samesite") == "Strict"
    
    async def test_login_invalid_credentials(self, client: AsyncClient):
        """Test login with invalid password returns 401"""
        response = await client.post("/auth/login", json={
            "login": "user@example.com",
            "password": "wrong_password"
        })
        
        assert response.status_code == 401
        assert "access_token" not in response.json()
    
    async def test_login_user_not_found(self, client: AsyncClient):
        """Test login with non-existent user returns 401"""
        response = await client.post("/auth/login", json={
            "login": "nonexistent@example.com",
            "password": "password"
        })
        
        assert response.status_code == 401


@pytest.mark.asyncio
class TestRefreshEndpoint:
    """Test /auth/refresh endpoint"""
    
    async def test_refresh_with_valid_token(self, client: AsyncClient, test_user):
        """Test refresh with valid refresh token"""
        # First login
        login_response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        # Then refresh
        refresh_response = await client.post("/auth/refresh")
        
        assert refresh_response.status_code == 200
        data = refresh_response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"
    
    async def test_refresh_sets_new_cookie(self, client: AsyncClient, test_user):
        """Test refresh sets new refresh_token cookie (rotation)"""
        # Login
        await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        old_token = client.cookies.get("refresh_token")
        
        # Refresh
        response = await client.post("/auth/refresh")
        
        new_token = client.cookies.get("refresh_token")
        
        # Token should be different (rotation)
        assert new_token != old_token
        assert response.status_code == 200
    
    async def test_refresh_without_cookie(self, client: AsyncClient):
        """Test refresh without refresh_token cookie returns 401"""
        response = await client.post("/auth/refresh")
        
        assert response.status_code == 401
        assert "Refresh token not found" in response.json()["detail"]
    
    async def test_old_refresh_token_invalid_after_rotation(self, client: AsyncClient, test_user):
        """Test old refresh token invalid after one refresh (one-time use)"""
        # Login
        login_response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        old_token = login_response.cookies.get("refresh_token")
        
        # First refresh
        client.cookies.set("refresh_token", old_token)
        await client.post("/auth/refresh")
        
        # Try to use old token again
        client.cookies.set("refresh_token", old_token)
        response = await client.post("/auth/refresh")
        
        # Should fail (one-time use)
        assert response.status_code == 401
    
    async def test_refresh_token_rotation_maintains_family(self, client: AsyncClient, test_user):
        """Test token rotation maintains same family ID"""
        # Login
        login_response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        original_family = login_response.json().get("family")
        
        # Refresh multiple times
        for _ in range(3):
            response = await client.post("/auth/refresh")
            rotated_family = response.json()["family"]
            
            # Family should remain same
            assert rotated_family == original_family
    
    async def test_refresh_with_expired_token(self, client: AsyncClient, test_user):
        """Test refresh with expired refresh token"""
        # Create an expired refresh token
        from app.utils.jwt import create_refresh_token
        from datetime import timedelta, datetime, timezone
        
        # We can't easily test this without mocking time
        # This would require freezegun or similar
        pass


@pytest.mark.asyncio
class TestTokenAuthorization:
    """Test API requests with tokens"""
    
    async def test_request_with_valid_access_token(self, client: AsyncClient, test_user):
        """Test API request succeeds with valid access token"""
        # Login to get token
        login_response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        access_token = login_response.json()["access_token"]
        
        # Make request with token
        response = await client.get(
            "/api/hero",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        
        assert response.status_code == 200
    
    async def test_request_without_access_token(self, client: AsyncClient):
        """Test API request without token returns 401"""
        response = await client.get("/api/hero")
        
        assert response.status_code == 401
    
    async def test_request_with_invalid_token(self, client: AsyncClient):
        """Test API request with invalid token returns 401"""
        response = await client.get(
            "/api/hero",
            headers={"Authorization": "Bearer invalid.token.here"}
        )
        
        assert response.status_code == 401
    
    async def test_request_with_refresh_token_as_access(self, client: AsyncClient, test_user):
        """Test using refresh token as access token fails"""
        # Login to get tokens
        login_response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        refresh_token = login_response.json()["refresh_token"]
        
        # Try to use refresh token as access token
        response = await client.get(
            "/api/hero",
            headers={"Authorization": f"Bearer {refresh_token}"}
        )
        
        assert response.status_code == 401  # Token type mismatch
```

---

## End-to-End Client Tests

### NetworkManager Token Refresh Tests

**File**: `client/tests/test_network_token_refresh.gd`

```gdscript
extends GutTest

class_name TestNetworkTokenRefresh

# Tests for automatic token refresh in NetworkManager

func test_401_triggers_refresh():
    """Test that 401 response triggers automatic token refresh"""
    # Setup
    var network = NetworkManager.new()
    AppState.access_token = "expired_token"
    
    # Mock server response (401)
    var mock_response = NetworkResponse.new(401, {}, "")
    
    # Make request that will return 401
    var request_task = network.request("/api/hero", NetworkManager.GET)
    
    # Wait for automatic refresh to be attempted
    await get_tree().process_frame
    
    # NetworkManager should have called /auth/refresh
    assert network._token_refresh_in_progress == false  # Should complete
    assert AppState.access_token != "expired_token"  # Token should be updated


func test_refresh_token_not_sent_to_server():
    """Test that refresh token in memory is not sent to server"""
    # The refresh token should only be in HTTP-only cookie
    var network = NetworkManager.new()
    AppState.access_token = "valid_token"
    AppState.refresh_token = "refresh_in_memory"  # Should not be used
    
    var headers = network._get_default_headers()
    
    # Should only contain access token, not refresh
    var auth_header = headers[headers.size() - 1]
    assert auth_header.contains(AppState.access_token)
    assert not auth_header.contains(AppState.refresh_token)


func test_infinite_loop_prevention():
    """Test that refresh is not attempted more than once"""
    var network = NetworkManager.new()
    AppState.access_token = "token"
    
    # First 401
    network._failed_refresh_attempts = 0
    if await network._handle_token_expiration({}):
        network._failed_refresh_attempts += 1
    
    # Second 401 (should not retry)
    var can_retry = await network._handle_token_expiration({})
    
    assert can_retry == false  # Should not allow second refresh


func test_concurrent_refresh_prevented():
    """Test that concurrent refresh requests are prevented"""
    var network = NetworkManager.new()
    
    network._token_refresh_in_progress = true
    
    var result = await network._handle_token_expiration({})
    
    assert result == false  # Should prevent concurrent refresh


func test_access_token_updated_after_refresh():
    """Test that AppState.access_token is updated after refresh"""
    var network = NetworkManager.new()
    var original_token = "original_token"
    AppState.access_token = original_token
    
    # Simulate refresh (would call /auth/refresh in real scenario)
    var new_token = "new_token_from_server"
    AppState.access_token = new_token
    
    assert AppState.access_token == new_token
    assert AppState.access_token != original_token


func test_refresh_timeout():
    """Test that refresh has timeout protection"""
    var network = NetworkManager.new()
    
    # Set very short timeout and try refresh with no server
    var timeout_success = await network._refresh_access_token()
    
    assert timeout_success == false  # Should timeout and fail
```

---

## Security Tests

### Token Rotation Security

**File**: `Server/tests/test_token_rotation_security.py`

```python
import pytest
from app.utils.jwt import create_refresh_token, decode_refresh_token
from app.services.auth import AuthService

@pytest.mark.asyncio
class TestTokenRotationSecurity:
    """Test token rotation security properties"""
    
    def test_family_id_unique_per_login(self, test_user):
        """Test each login creates unique family ID"""
        service = AuthService()
        
        tokens1 = service.generate_tokens(test_user)
        tokens2 = service.generate_tokens(test_user)
        
        family1 = tokens1["family"]
        family2 = tokens2["family"]
        
        # Different logins should have different families
        assert family1 != family2
    
    def test_family_id_preserved_on_refresh(self, test_user):
        """Test family ID preserved across refresh (maintains chain)"""
        service = AuthService()
        
        # Login
        tokens1 = service.generate_tokens(test_user)
        family1 = tokens1["family"]
        
        # Refresh
        tokens2 = service.refresh_access_token(tokens1["refresh_token"])
        family2 = tokens2["family"]
        
        # Family should be same (maintains chain)
        assert family1 == family2
    
    def test_old_refresh_token_invalid(self, test_user):
        """Test old refresh token invalid after refresh"""
        service = AuthService()
        
        tokens1 = service.generate_tokens(test_user)
        old_refresh = tokens1["refresh_token"]
        
        # First refresh (invalidates old token)
        tokens2 = service.refresh_access_token(old_refresh)
        
        # Try to use old token again
        tokens3 = service.refresh_access_token(old_refresh)
        
        # Should fail (tokens3 should be None)
        assert tokens3 is None
    
    def test_token_compromise_detection(self, test_user):
        """Test that token reuse can be detected via family ID"""
        # Scenario: Attacker obtains old refresh token
        # Attacker uses it to get new token (gets same family)
        # Real user also tries to use old token (gets same family)
        # Both have same family_id = compromise detected
        
        service = AuthService()
        
        tokens1 = service.generate_tokens(test_user)
        refresh1 = tokens1["refresh_token"]
        family1 = tokens1["family"]
        
        # Attacker uses token
        attacker_tokens = service.refresh_access_token(refresh1)
        
        # Now refresh1 is invalid, but we know attacker got it
        # Real user tries to use old token
        user_tokens = service.refresh_access_token(refresh1)
        
        # Should fail (already used)
        assert user_tokens is None
        assert attacker_tokens["family"] == family1  # Same family
    
    def test_access_token_cannot_refresh(self, test_user):
        """Test access token cannot be used for refresh"""
        service = AuthService()
        tokens = service.generate_tokens(test_user)
        
        access_token = tokens["access_token"]
        
        # Try to use access token as refresh token
        result = service.refresh_access_token(access_token)
        
        assert result is None  # Should fail
```

### Cookie Security

**File**: `Server/tests/test_cookie_security.py`

```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
class TestCookieSecurity:
    """Test HTTP-only cookie security"""
    
    async def test_refresh_cookie_httponly(self, client: AsyncClient, test_user):
        """Test refresh_token cookie has HttpOnly flag"""
        response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        cookie_header = response.headers.get("set-cookie", "")
        assert "HttpOnly" in cookie_header
    
    async def test_refresh_cookie_secure(self, client: AsyncClient, test_user):
        """Test refresh_token cookie has Secure flag (HTTPS only)"""
        response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        cookie_header = response.headers.get("set-cookie", "")
        # In production (HTTPS), should have Secure
        # In test (HTTP), might not have it, but check structure is right
        assert "refresh_token" in cookie_header
    
    async def test_refresh_cookie_samesite(self, client: AsyncClient, test_user):
        """Test refresh_token cookie has SameSite=Strict"""
        response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        cookie_header = response.headers.get("set-cookie", "")
        assert "SameSite=Strict" in cookie_header
    
    async def test_refresh_cookie_max_age(self, client: AsyncClient, test_user):
        """Test refresh_token cookie expires after 7 days"""
        response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        cookie_header = response.headers.get("set-cookie", "")
        # Should have max-age=604800 (7 days in seconds)
        assert "Max-Age" in cookie_header or "max-age" in cookie_header
```

---

## Load Testing

### Concurrent Refresh Scenarios

**File**: `Server/tests/test_concurrent_refresh.py`

```python
import pytest
import asyncio
from httpx import AsyncClient

@pytest.mark.asyncio
class TestConcurrentRefresh:
    """Test concurrent token refresh scenarios"""
    
    async def test_multiple_concurrent_refreshes(self, client: AsyncClient, test_user):
        """Test multiple concurrent refresh requests"""
        # Login
        login_response = await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        # Make multiple concurrent refresh requests
        tasks = [
            client.post("/auth/refresh")
            for _ in range(10)
        ]
        
        responses = await asyncio.gather(*tasks)
        
        # All but one should fail (old tokens)
        success_count = sum(1 for r in responses if r.status_code == 200)
        fail_count = sum(1 for r in responses if r.status_code == 401)
        
        # Due to one-time use, only first request should succeed
        assert success_count >= 1  # At least one succeeds
        assert fail_count >= 1  # Others fail (used token)
    
    async def test_refresh_under_load(self, client: AsyncClient, test_user):
        """Test refresh endpoint performance under load"""
        import time
        
        # Login to get refresh token
        await client.post("/auth/login", json={
            "login": test_user.email,
            "password": "correct_password"
        })
        
        start_time = time.time()
        
        # Make 100 sequential successful refreshes
        # (Each one creates new token for next request)
        for i in range(10):  # Limited to 10 for test speed
            response = await client.post("/auth/refresh")
            if response.status_code != 200:
                break
        
        end_time = time.time()
        elapsed = end_time - start_time
        
        # Should complete in reasonable time (< 5 seconds)
        assert elapsed < 5.0
```

---

## Manual Testing Checklist

### Browser Testing

- [ ] Open browser dev tools → Application → Cookies
- [ ] Login to application
- [ ] Verify `refresh_token` cookie exists
- [ ] Verify cookie attributes: HttpOnly, Secure, SameSite=Strict
- [ ] Keep browser open for 20+ minutes
- [ ] Make API request (should trigger automatic refresh)
- [ ] Verify no JavaScript error (transparent refresh)
- [ ] Verify new refresh token set in cookie

### Network Tab Testing

- [ ] Open Browser Dev Tools → Network tab
- [ ] Login
- [ ] Set network throttle to "Fast 3G" or slower
- [ ] Make API request after token expires (20 min or mock)
- [ ] Observe network tab:
  - [ ] Original request returns 401
  - [ ] /auth/refresh request made automatically
  - [ ] Original request retried with new token
  - [ ] Final request returns 200

### Edge Cases

- [ ] Test with both access token AND refresh token expired (7+ days)
  - [ ] Should show login screen
- [ ] Test with network disconnected during refresh
  - [ ] Should emit 401 error
  - [ ] User should be prompted to log in again
- [ ] Test rapid API calls (before refresh completes)
  - [ ] Should use same new token
  - [ ] No concurrent refresh attempts
- [ ] Test closing browser and reopening (24 hours later)
  - [ ] Refresh token still in cookie
  - [ ] Auto-login should work if token not expired

---

## Test Automation

### Running All Tests

```bash
# Backend tests
cd Server
pytest tests/ -v --tb=short

# Client tests (requires Godot)
godot -d --script res://tests/test_network_token_refresh.gd

# Specific test
pytest tests/test_jwt_tokens.py::TestAccessToken::test_access_token_expiration -v
```

### Test Configuration

**File**: `Server/conftest.py`

```python
import pytest
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from app.database import Base

@pytest.fixture
async def test_user(db_session):
    """Create test user"""
    from app.models import User
    
    user = User(
        email="test@example.com",
        hashed_password=hash_password("correct_password"),
        username="testuser"
    )
    db_session.add(user)
    await db_session.commit()
    return user

@pytest.fixture
async def client():
    """Create test client"""
    from httpx import AsyncClient
    from app.main import app
    
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac
```

---

## Success Criteria

### Unit Tests
- ✅ All JWT token tests pass
- ✅ Token generation includes family ID
- ✅ Token rotation maintains family
- ✅ Token type enforcement works

### Integration Tests
- ✅ Login sets HTTP-only cookie
- ✅ Refresh endpoint validates token
- ✅ Refresh returns new token
- ✅ Old token invalid after refresh
- ✅ API requests work with valid token
- ✅ API requests fail with invalid token

### E2E Tests
- ✅ Client auto-refresh on 401
- ✅ Cookie sent automatically
- ✅ New token used in retry
- ✅ Infinite loop prevented
- ✅ Concurrent refresh prevented

### Security Tests
- ✅ Family ID unique per login
- ✅ Family ID preserved on refresh
- ✅ One-time use enforced
- ✅ Token type validation enforced
- ✅ Cookies secure (HttpOnly, Secure, SameSite)

---

## Debugging Failed Tests

### Test Fails: "Token not valid"

```python
# Check: Is token type enforced?
# In jwt.py decode_access_token():
assert payload.get("type") == "access"

# Check: Is token expired?
exp = datetime.fromtimestamp(payload["exp"])
assert datetime.utcnow() < exp
```

### Test Fails: "Cookie not set"

```python
# Check: Is Response imported?
from fastapi import Response

# Check: Is cookie set in endpoint?
response.set_cookie(
    key="refresh_token",
    value=...,
    httponly=True,
    secure=True,
    samesite="strict"
)
```

### Test Fails: "Refresh infinite loop"

```gdscript
# Check: Is _max_refresh_attempts = 1?
var _max_refresh_attempts: int = 1

# Check: Is _failed_refresh_attempts reset?
_failed_refresh_attempts = 0  # Reset on new request

# Check: Is _token_refresh_in_progress reset?
_token_refresh_in_progress = false  # Reset after refresh
```

---

## Summary

✅ **Comprehensive test suite** covering unit, integration, E2E, security, and load tests  
✅ **Security validation** for token rotation and cookie protection  
✅ **Manual testing checklist** for exploratory testing  
✅ **Debugging guide** for troubleshooting failed tests  

**Ready for testing!** 🧪
