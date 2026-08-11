# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

"""A minimal DAG used by the Core Operations UAT to validate the local DAG bundle."""

from __future__ import annotations

import pendulum
from airflow.sdk import dag, task


@dag(
    dag_id="uat_print_message_dag",
    schedule=None,
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    catchup=False,
    tags=["uat"],
)
def uat_print_message_dag():
    @task
    def print_message():
        print("Hello from the Charmed Airflow UAT!")

    print_message()


uat_print_message_dag()