from app import auth


def test_secret_is_created_once_and_reused(tmp_path):
    f = tmp_path / ".jwt_secret"
    first = auth.load_or_create_secret(f)
    assert len(first) >= 32
    assert auth.load_or_create_secret(f) == first  # same key after a "restart"


def test_short_or_corrupt_secret_is_replaced(tmp_path):
    f = tmp_path / ".jwt_secret"
    f.write_text("short")
    assert len(auth.load_or_create_secret(f)) >= 32
