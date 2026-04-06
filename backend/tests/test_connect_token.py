import time

from app.connect_token import issue_connect_token, verify_token, create_token


def test_issue_and_verify():
    token = issue_connect_token(
        "u1", "ABCD", "player",
        display_name="Alice",
        seat_index=1,
        generation=7,
        config_json='{"desired_player_count":2}',
        join_policy="password",
        password_hash="hashed-password",
    )
    payload = verify_token(token)
    assert payload is not None
    assert payload["user_id"] == "u1"
    assert payload["room_code"] == "ABCD"
    assert payload["role"] == "player"
    assert payload["display_name"] == "Alice"
    assert payload["seat_index"] == 1
    assert payload["generation"] == 7
    assert payload["config_json"] == '{"desired_player_count":2}'
    assert payload["join_policy"] == "password"
    assert payload["password_hash"] == "hashed-password"


def test_expired_token_rejected():
    token = create_token({"user_id": "u1", "exp": int(time.time()) - 10})
    assert verify_token(token) is None


def test_tampered_token_rejected():
    token = issue_connect_token("u1", "ABCD", "player")
    assert verify_token(token + "x") is None


def test_malformed_token_rejected():
    assert verify_token("not-a-token") is None
    assert verify_token("") is None
