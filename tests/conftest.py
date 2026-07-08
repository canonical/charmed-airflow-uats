# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

"""Fixtures for Airflow UATs."""


def pytest_addoption(parser):
    parser.addoption(
        "--airflow-model",
        action="store",
        help="Model for Charmed Airflow",
    )
    parser.addoption(
        "--identity-model",
        action="store",
        help="Model for Canonical Identity Platform",
    )
