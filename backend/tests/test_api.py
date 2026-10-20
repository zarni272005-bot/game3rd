import os
import tempfile
from pathlib import Path

import pytest

_test_directory = tempfile.TemporaryDirectory(prefix="island-arena-tests-")
os.environ["DATABASE_URL"] = f"sqlite:///{(Path(_test_directory.name) / 'arena.db').as_posix()}"

from fastapi.testclient import TestClient

from backend.main import app, engine


@pytest.fixture(scope="session", autouse=True)
def close_test_database():
    yield
    engine.dispose()
    _test_directory.cleanup()


def test_health_reports_storage() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "storage": "ok"}


def test_match_lifecycle() -> None:
    with TestClient(app) as client:
        created = client.post(
            "/v1/matches",
            json={"map_name": "test island", "max_players": 8},
        )
        assert created.status_code == 201
        match = created.json()
        assert match["map_name"] == "test island"
        assert match["status"] == "open"

        updated = client.patch(
            f"/v1/matches/{match['id']}",
            json={"status": "in_progress"},
        )
        assert updated.status_code == 200
        assert updated.json()["status"] == "in_progress"

        listed = client.get("/v1/matches", params={"status": "in_progress"})
        assert listed.status_code == 200
        assert any(item["id"] == match["id"] for item in listed.json())


def test_match_input_is_validated() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/v1/matches",
            json={"map_name": "island", "max_players": 1000},
        )

    assert response.status_code == 422
