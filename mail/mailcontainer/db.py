"""Postgres: the connection (libpq's PG* variables), the wake-up channels, sync_state."""

import json

import psycopg
from psycopg.rows import dict_row

OUTBOX = "n8n_workshop_mail_outbox"
SYNC = "n8n_workshop_mail_sync"


def connect(**kwargs):
    return psycopg.connect(autocommit=True, row_factory=dict_row, application_name="mail-container", **kwargs)


def listen(conn):
    for channel in (OUTBOX, SYNC):
        conn.execute(f"LISTEN {channel}")


def wake(conn, **payload):
    """Ask the running service for work, e.g. wake(conn, action='sync', source='watcher')."""
    conn.execute("SELECT pg_notify(%s, %s)", (SYNC, json.dumps(payload)))


def note_run(conn, ok, error=None):
    if ok:
        conn.execute("UPDATE n8n_workshop_mail.sync_state SET last_run_at = now(), last_ok_at = now()")
    else:
        conn.execute("""UPDATE n8n_workshop_mail.sync_state
                           SET last_run_at = now(), last_error = %s, last_error_at = now()""", (error[:4000],))


def note_error(conn, error):
    conn.execute("UPDATE n8n_workshop_mail.sync_state SET last_error = %s, last_error_at = now()", (error[:4000],))
