"""Mail container for the n8n workshop: keeps a mailbox and Postgres in step, sends what a person approved.

The only place that knows the mailbox password. Talks to the provider through mbsync (IMAP) and
smtplib (SMTP), to n8n only through Postgres (schema n8n_workshop_mail): rows, and NOTIFY as wake-up calls.
"""

__version__ = "0.1.0"
