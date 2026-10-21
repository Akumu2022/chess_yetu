import os

# Must be set before app modules are imported.
os.environ["DATABASE_URL"] = os.environ.get("TEST_DATABASE_URL", "sqlite:///:memory:")  # e.g. a throwaway Postgres
os.environ.setdefault("JWT_SECRET", "test-secret-test-secret-test-secret-0123")
