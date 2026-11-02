-- Schema "n8n_workshop_mail" for the mail assistant (n8n workshop, Workshop II).
--
-- Run as a superuser (the pod user `student`) in database `classroom`, on a Postgres with pgvector
-- (the pod's image pgvector/pgvector:pg16-trixie).
-- Idempotent: safe to run on every `kingo up`, which does so. No passwords here; `kingo up` sets them.
--
-- Who writes what (tables in schema n8n_workshop_mail):
--   messages    the mail container; everyone else reads
--   outbox      n8n proposes (content columns only) and approves via approve(); the container
--               moves the status on; a trigger allows only the documented steps
--   changes     n8n asks for a change to a mail already there (read, star, archive, label); the
--               container carries it out and sets the status. Nothing deletes a mail.
--   processed   n8n claims a mail per workflow, then writes its result
--   sync_state  the container
--   seeded      the container, when `kingo mail seed` put the case mailbox into an account
--   calendar    `kingo up` makes it a copy of the course case's (case/calendar.csv); n8n and
--               Langflow read
--   chunks      n8n embeds the mails ("Einbetten"), `kingo mail seed` loads the case documents;
--               Langflow searches, "Draft Reply" without the internal rows (row level security)
--   cases       the test bench's test cases; n8n imports them (the course's, a team's Excel)
--   results     the test bench, one row per case and run; nobody else reads either table
--
-- Roles: n8n_workshop_mail_ + container, n8n, agent, reply.
-- Channels (LISTEN):
--   n8n_workshop_mail_new     new rows in messages (payload: number of new rows)
--   n8n_workshop_mail_outbox  an outbox row was approved (payload: its id)
--   n8n_workshop_mail_sync    sync, test-mail or changes request for the container (payload: JSON)
--
-- Message-IDs are stored without angle brackets, as notmuch shows them.

SET client_min_messages = warning;  -- quiet on every `kingo up`: no "already exists, skipping"

BEGIN;

CREATE SCHEMA IF NOT EXISTS n8n_workshop_mail;
COMMENT ON SCHEMA n8n_workshop_mail IS 'Mail assistant: mailbox rows, outbox, results. Schema version 1.';

-- Roles are cluster-wide. LOGIN without password; `kingo up` sets the passwords.
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['n8n_workshop_mail_container', 'n8n_workshop_mail_n8n',
                           'n8n_workshop_mail_agent', 'n8n_workshop_mail_reply'] LOOP
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I LOGIN', r);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Messages: one row per mail in the mailbox
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.messages (
  message_id    text PRIMARY KEY
                CHECK (message_id <> '' AND left(message_id, 1) <> '<' AND right(message_id, 1) <> '>'),
  thread_id     text,
  folders       text[] NOT NULL DEFAULT '{}',   -- local folder names: INBOX, Sent, Drafts, All Mail (Gmail)
  from_addr     text,                           -- bare address, lower case
  from_name     text,                           -- display name of the sender, if any
  to_addrs      text[] NOT NULL DEFAULT '{}',   -- bare addresses, lower case
  cc_addrs      text[] NOT NULL DEFAULT '{}',
  subject       text,
  sent_at       timestamptz,
  body_text     text,
  body_html     text,
  tags          text[] NOT NULL DEFAULT '{}',   -- unread, replied, flagged, draft; test for test mails
  attachments   jsonb NOT NULL DEFAULT '[]',    -- [{name, type, size}]
  in_reply_to   text,                           -- no foreign key: the parent may not be in the mailbox
  reply_headers jsonb,                          -- {to, cc, subject, in_reply_to, references} for a reply;
                                                -- to and cc as 'Name <address>', ready for outbox
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),  -- first seen; for measuring delay
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Added after the first load into classroom (25 Oct 2026); a no-op on new databases.
ALTER TABLE n8n_workshop_mail.messages ADD COLUMN IF NOT EXISTS from_name text;

-- The words of each mail for Mail Lookup, the classic search (like the search box of Gmail or
-- Fastmail): subject, sender's name and text, as English word forms. Only the first 100,000
-- characters count, so that a huge mail still loads (a tsvector holds at most 1 MB). Added on
-- 29 Oct 2026; on a database loaded before, Postgres fills it for every row once.
ALTER TABLE n8n_workshop_mail.messages ADD COLUMN IF NOT EXISTS tsv tsvector GENERATED ALWAYS AS (
  to_tsvector('english', left(coalesce(subject, '') || ' ' || coalesce(from_name, '') || ' ' || coalesce(body_text, ''),
                              100000))) STORED;
CREATE INDEX IF NOT EXISTS messages_tsv_idx ON n8n_workshop_mail.messages USING gin (tsv);

CREATE INDEX IF NOT EXISTS messages_thread_idx  ON n8n_workshop_mail.messages (thread_id);
CREATE INDEX IF NOT EXISTS messages_sent_at_idx ON n8n_workshop_mail.messages (sent_at DESC);
CREATE INDEX IF NOT EXISTS messages_tags_idx    ON n8n_workshop_mail.messages USING gin (tags);
CREATE INDEX IF NOT EXISTS messages_folders_idx ON n8n_workshop_mail.messages USING gin (folders);

CREATE OR REPLACE FUNCTION n8n_workshop_mail.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS messages_touch ON n8n_workshop_mail.messages;
CREATE TRIGGER messages_touch BEFORE UPDATE ON n8n_workshop_mail.messages
  FOR EACH ROW EXECUTE FUNCTION n8n_workshop_mail.touch_updated_at();

-- One NOTIFY per statement that inserted rows, whoever inserted them.
-- With INSERT ... ON CONFLICT DO UPDATE, only rows actually inserted count.
CREATE OR REPLACE FUNCTION n8n_workshop_mail.notify_new_messages() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n FROM new_rows;
  IF n > 0 THEN
    PERFORM pg_notify('n8n_workshop_mail_new', n::text);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS messages_notify_new ON n8n_workshop_mail.messages;
CREATE TRIGGER messages_notify_new AFTER INSERT ON n8n_workshop_mail.messages
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION n8n_workshop_mail.notify_new_messages();

-- ---------------------------------------------------------------------------
-- Outbox: proposals, approval, sending
-- ---------------------------------------------------------------------------
--
--   proposed -> approved (n8n_workshop_mail.approve) | rejected (n8n_workshop_mail.reject)
--   expired  -> approved | rejected
--   approved -> drafting | sending | expired        (drafting/sending only within 24 h of approval)
--   drafting -> drafted
--   sending  -> sent | sent_without_copy | failed
--   sent_without_copy -> sent
--   drafted, sent, failed, rejected are final. A row stuck in drafting or sending is checked by a person.

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.outbox (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mode        text NOT NULL CHECK (mode IN ('draft', 'send')),
  to_addrs    text[] NOT NULL CHECK (cardinality(to_addrs) > 0),
  cc_addrs    text[] NOT NULL DEFAULT '{}',
  subject     text NOT NULL,
  body        text NOT NULL,
  in_reply_to text REFERENCES n8n_workshop_mail.messages (message_id),
  status      text NOT NULL DEFAULT 'proposed'
              CHECK (status IN ('proposed', 'approved', 'rejected', 'expired', 'drafting', 'drafted',
                                'sending', 'sent', 'sent_without_copy', 'failed')),
  reason      text,         -- the person's reason in the approval form (approve or reject)
  approved_by text,
  approved_at timestamptz,
  rejected_by text,
  rejected_at timestamptz,
  message_id  text,         -- set by the container: Message-ID of the mail it built
  raw         text,         -- set by the container: the finished mail
  error       text,         -- set by the container: why it failed, refused recipients
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- At most one open proposal per original mail.
CREATE UNIQUE INDEX IF NOT EXISTS outbox_one_open_per_original ON n8n_workshop_mail.outbox (in_reply_to)
  WHERE status IN ('proposed', 'approved', 'expired', 'drafting', 'sending');
CREATE INDEX IF NOT EXISTS outbox_status_idx ON n8n_workshop_mail.outbox (status);

CREATE OR REPLACE FUNCTION n8n_workshop_mail.outbox_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  allowed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'proposed' THEN
      RAISE EXCEPTION 'outbox: a new row must be proposed, not %', NEW.status;
    END IF;
    IF num_nonnulls(NEW.reason, NEW.approved_by, NEW.approved_at, NEW.rejected_by, NEW.rejected_at,
                    NEW.message_id, NEW.raw, NEW.error) > 0 THEN
      RAISE EXCEPTION 'outbox: a new row carries only its content';
    END IF;
    NEW.created_at := now();
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  -- UPDATE. The content is fixed once proposed; only n8n_workshop_mail.approve may replace the body, in the
  -- same step as the approval, so that what goes out is exactly what the person approved.
  IF (NEW.id, NEW.mode, NEW.to_addrs, NEW.cc_addrs, NEW.subject, NEW.in_reply_to, NEW.created_at)
     IS DISTINCT FROM (OLD.id, OLD.mode, OLD.to_addrs, OLD.cc_addrs, OLD.subject, OLD.in_reply_to, OLD.created_at) THEN
    RAISE EXCEPTION 'outbox %: content is fixed once proposed; reject it and propose a new row', OLD.id;
  END IF;
  IF NEW.body IS DISTINCT FROM OLD.body
     AND NOT (OLD.status IN ('proposed', 'expired') AND NEW.status = 'approved') THEN
    RAISE EXCEPTION 'outbox %: the body can change only with the approval', OLD.id;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    allowed := CASE OLD.status
      WHEN 'proposed'          THEN NEW.status IN ('approved', 'rejected')
      WHEN 'expired'           THEN NEW.status IN ('approved', 'rejected')
      WHEN 'approved'          THEN NEW.status IN ('drafting', 'sending', 'expired')
      WHEN 'drafting'          THEN NEW.status = 'drafted'
      WHEN 'sending'           THEN NEW.status IN ('sent', 'sent_without_copy', 'failed')
      WHEN 'sent_without_copy' THEN NEW.status = 'sent'
      ELSE false
    END;
    IF NOT allowed THEN
      RAISE EXCEPTION 'outbox %: % -> % is not allowed', OLD.id, OLD.status, NEW.status;
    END IF;
    IF NEW.status IN ('drafting', 'sending') AND OLD.approved_at < now() - interval '24 hours' THEN
      RAISE EXCEPTION 'outbox %: the approval is older than 24 hours; set it to expired', OLD.id;
    END IF;
  END IF;

  -- Who decided, and why, is written only together with that decision.
  IF (NEW.approved_by, NEW.approved_at) IS DISTINCT FROM (OLD.approved_by, OLD.approved_at)
     AND NOT (NEW.status = 'approved' AND OLD.status IN ('proposed', 'expired')) THEN
    RAISE EXCEPTION 'outbox %: approved_by and approved_at are set only by the approval', OLD.id;
  END IF;
  IF (NEW.rejected_by, NEW.rejected_at) IS DISTINCT FROM (OLD.rejected_by, OLD.rejected_at)
     AND NOT (NEW.status = 'rejected' AND OLD.status IN ('proposed', 'expired')) THEN
    RAISE EXCEPTION 'outbox %: rejected_by and rejected_at are set only by the rejection', OLD.id;
  END IF;
  IF NEW.reason IS DISTINCT FROM OLD.reason
     AND NOT (NEW.status IN ('approved', 'rejected') AND OLD.status IN ('proposed', 'expired')) THEN
    RAISE EXCEPTION 'outbox %: the reason is set only with a decision', OLD.id;
  END IF;
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved'
     AND (NEW.approved_by IS NULL OR btrim(NEW.approved_by) = '' OR NEW.approved_at IS NULL) THEN
    RAISE EXCEPTION 'outbox %: an approval needs a name and a time', OLD.id;
  END IF;

  NEW.updated_at := now();

  -- NOTIFY is delivered at commit, so a failed transaction sends nothing.
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
    PERFORM pg_notify('n8n_workshop_mail_outbox', NEW.id::text);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS outbox_guard ON n8n_workshop_mail.outbox;
CREATE TRIGGER outbox_guard BEFORE INSERT OR UPDATE ON n8n_workshop_mail.outbox
  FOR EACH ROW EXECUTE FUNCTION n8n_workshop_mail.outbox_guard();

-- ---------------------------------------------------------------------------
-- Processed: which workflow has claimed which mail, and its result
-- ---------------------------------------------------------------------------
-- Changes: n8n asks the container to change a mail already in the mailbox
-- ---------------------------------------------------------------------------
--
--   read, unread, star, unstar   flags, with every provider
--   archive, inbox               out of the inbox and back (Gmail only: there it takes the label
--                                Inbox off or puts it back; the mail stays in All Mail)
--   label, unlabel               the label Assistant/<label> (Gmail only)
--
--   pending -> done | failed (the container). done: changed in the local mailbox; mbsync carries it
--   to the provider on its next run, seconds later. No approval: nothing leaves the mailbox, and
--   nothing is deleted.

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.changes (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  message_id text NOT NULL REFERENCES n8n_workshop_mail.messages (message_id),
  action     text NOT NULL CHECK (action IN ('read', 'unread', 'star', 'unstar', 'archive', 'inbox', 'label', 'unlabel')),
  label      text CHECK (label ~ '^[A-Za-z0-9][A-Za-z0-9 _-]{0,39}$'),
  status     text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'failed')),
  error      text,         -- set by the container: why it failed
  created_at timestamptz NOT NULL DEFAULT now(),
  done_at    timestamptz,
  CHECK ((action IN ('label', 'unlabel')) = (label IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS changes_pending_idx ON n8n_workshop_mail.changes (id) WHERE status = 'pending';

CREATE OR REPLACE FUNCTION n8n_workshop_mail.notify_changes() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_notify('n8n_workshop_mail_sync', json_build_object('action', 'changes')::text);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS changes_notify ON n8n_workshop_mail.changes;
CREATE TRIGGER changes_notify AFTER INSERT ON n8n_workshop_mail.changes
  FOR EACH STATEMENT EXECUTE FUNCTION n8n_workshop_mail.notify_changes();

-- ---------------------------------------------------------------------------
-- Claim:  INSERT INTO n8n_workshop_mail.processed (message_id, workflow, execution_id) VALUES (...) ON CONFLICT DO NOTHING
-- Result: UPDATE n8n_workshop_mail.processed SET result = ... WHERE message_id = ... AND workflow = ...
-- Error workflow: DELETE FROM n8n_workshop_mail.processed WHERE execution_id = ... AND result IS NULL

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.processed (
  message_id   text NOT NULL REFERENCES n8n_workshop_mail.messages (message_id) ON DELETE CASCADE,
  workflow     text NOT NULL CHECK (workflow <> ''),
  execution_id text,
  result       jsonb,
  claimed_at   timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  PRIMARY KEY (message_id, workflow)
);

CREATE INDEX IF NOT EXISTS processed_execution_idx ON n8n_workshop_mail.processed (execution_id);

CREATE OR REPLACE FUNCTION n8n_workshop_mail.processed_stamp() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.result IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.result IS NULL) THEN
    NEW.processed_at := now();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS processed_stamp ON n8n_workshop_mail.processed;
CREATE TRIGGER processed_stamp BEFORE INSERT OR UPDATE ON n8n_workshop_mail.processed
  FOR EACH ROW EXECUTE FUNCTION n8n_workshop_mail.processed_stamp();

-- ---------------------------------------------------------------------------
-- Sync state: one row, written by the container
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.sync_state (
  id            boolean PRIMARY KEY DEFAULT true CHECK (id),
  notmuch_uuid  text,
  last_revision bigint,
  last_run_at   timestamptz,
  last_ok_at    timestamptz,
  last_error    text,          -- also refusals by the provider, e.g. a mail over its size limit
  last_error_at timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now()
);
INSERT INTO n8n_workshop_mail.sync_state (id) VALUES (true) ON CONFLICT DO NOTHING;

DROP TRIGGER IF EXISTS sync_state_touch ON n8n_workshop_mail.sync_state;
CREATE TRIGGER sync_state_touch BEFORE UPDATE ON n8n_workshop_mail.sync_state
  FOR EACH ROW EXECUTE FUNCTION n8n_workshop_mail.touch_updated_at();

-- Accounts that got the case mailbox. Here and not in the mail volume, which `kingo mail reset`
-- deletes: seeding the same account again would upload every mail a second time.
CREATE TABLE IF NOT EXISTS n8n_workshop_mail.seeded (
  address   text PRIMARY KEY CHECK (address = lower(address)),
  seeded_at timestamptz NOT NULL DEFAULT now(),
  folders   jsonb                -- mails per folder, e.g. {"All Mail": 160, "Sent": 42}
);

-- ---------------------------------------------------------------------------
-- Financial calendar (course case): rules need data, not text
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.calendar (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event      text NOT NULL,
  event_date date NOT NULL,
  quiet_from date,
  quiet_to   date,
  CHECK ((quiet_from IS NULL) = (quiet_to IS NULL)),
  CHECK (quiet_from IS NULL OR quiet_from <= quiet_to),
  UNIQUE (event, event_date)
);

-- The date that counts is the date of the mail, not the day the test bench runs.
CREATE OR REPLACE FUNCTION n8n_workshop_mail.in_quiet_period(d date) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT FROM n8n_workshop_mail.calendar WHERE d BETWEEN quiet_from AND quiet_to)
$$;

-- ---------------------------------------------------------------------------
-- Chunks: mails and documents as pieces of text, with a vector and full text, for search
-- ---------------------------------------------------------------------------
-- n8n writes the mails' chunks with the PGVector Store node (columns id, text, metadata,
-- embedding; "Skip Table Initialization" on). `kingo mail seed` writes the case documents with
-- vectors made in advance. Postgres fills visibility (from metadata) and tsv (from text) itself.
-- The model is baai/bge-m3 on OpenRouter, 1024 dimensions; it also runs locally (e.g. in Ollama).
-- An HNSW index finds the nearest chunks without comparing the question with every one. Its
-- result is approximate (it can miss a near chunk), which at a mailbox's size hardly ever shows.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.chunks (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  text       text NOT NULL,
  metadata   jsonb NOT NULL,     -- a mail's: message_id, thread_id, from, date, subject; a document's: doc, title, date
  embedding  vector(1024) NOT NULL,
  -- Set by whoever embeds; without it the insert fails rather than a row turning up too visible.
  visibility text GENERATED ALWAYS AS (metadata->>'visibility') STORED NOT NULL
             CHECK (visibility IN ('public', 'mail', 'internal')),
  tsv        tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS chunks_embedding_idx ON n8n_workshop_mail.chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS chunks_tsv_idx ON n8n_workshop_mail.chunks USING gin (tsv);
CREATE INDEX IF NOT EXISTS chunks_message_idx ON n8n_workshop_mail.chunks ((metadata->>'message_id'));
CREATE INDEX IF NOT EXISTS chunks_doc_idx ON n8n_workshop_mail.chunks ((metadata->>'doc'));
-- Mail Search with whole threads fetches the mails of the threads it found.
CREATE INDEX IF NOT EXISTS chunks_thread_idx ON n8n_workshop_mail.chunks ((metadata->>'thread_id'));

-- Who sees which rows. The filter sits in the database, not in a prompt or a field of a Langflow
-- component, so neither a tweak nor an agent with an SQL tool gets around it. The owner (the pod
-- user) is not subject to it.
ALTER TABLE n8n_workshop_mail.chunks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_all ON n8n_workshop_mail.chunks;
CREATE POLICY read_all ON n8n_workshop_mail.chunks FOR SELECT
  TO n8n_workshop_mail_agent, n8n_workshop_mail_n8n USING (true);
DROP POLICY IF EXISTS read_external ON n8n_workshop_mail.chunks;
CREATE POLICY read_external ON n8n_workshop_mail.chunks FOR SELECT
  TO n8n_workshop_mail_reply USING (visibility IN ('public', 'mail'));
-- n8n writes everything but the case documents, the mail container only those.
DROP POLICY IF EXISTS write_mail ON n8n_workshop_mail.chunks;
CREATE POLICY write_mail ON n8n_workshop_mail.chunks FOR ALL
  TO n8n_workshop_mail_n8n USING (NOT metadata ? 'doc') WITH CHECK (NOT metadata ? 'doc');
DROP POLICY IF EXISTS write_documents ON n8n_workshop_mail.chunks;
CREATE POLICY write_documents ON n8n_workshop_mail.chunks FOR ALL
  TO n8n_workshop_mail_container USING (metadata ? 'doc') WITH CHECK (metadata ? 'doc');

-- The HNSW index hands over its nearest candidates first (40 by default), and only then do the
-- filters run: row level security, a WHERE. With more internal rows than that among the nearest,
-- "Draft Reply" would get fewer hits than it asked for, or none. An iterative scan (pgvector 0.8)
-- keeps searching until enough rows pass. A role's settings apply when it logs in, as n8n and
-- Langflow do. (Up to a few thousand chunks Postgres reads the table instead, and the question
-- does not arise.)
ALTER ROLE n8n_workshop_mail_n8n SET hnsw.iterative_scan = relaxed_order;
ALTER ROLE n8n_workshop_mail_agent SET hnsw.iterative_scan = relaxed_order;
ALTER ROLE n8n_workshop_mail_reply SET hnsw.iterative_scan = relaxed_order;

-- ---------------------------------------------------------------------------
-- Test bench: test cases, and one result per case and run
-- ---------------------------------------------------------------------------
-- n8n imports the cases (the course's from Canvas, a team's from its Demo Day Excel), runs them
-- through the same core as the live workflow, without sending, and writes one row per case into
-- results. Accuracy per run, the spread over runs and the slowest cases are SQL. Only n8n reads
-- these tables: a flow that drafts must never see a reference answer.

CREATE TABLE IF NOT EXISTS n8n_workshop_mail.cases (
  test_set         text NOT NULL CHECK (test_set <> ''),   -- e.g. 'enron', or a team's test set
  case_id          text NOT NULL CHECK (case_id <> ''),    -- e.g. 'T008', 'S01', a row of the Excel
  tags             text[] NOT NULL DEFAULT '{}',           -- e.g. start, draft, injection; a run picks by tag
  sent_at          timestamptz,     -- the date of the mail: rules and search go by it, not by today
  from_name        text,
  from_addr        text,
  to_addrs         text[] NOT NULL DEFAULT '{}',           -- the mail's To and Cc, as the system sees them
  cc_addrs         text[] NOT NULL DEFAULT '{}',
  subject          text,
  input            text NOT NULL,   -- the mail's text, or the request
  test_mail        integer,         -- the same case as a mail in the inbox: deliver_test(n)
  expected_action  text,            -- category or decision, compared exactly
  expected_sources text[] NOT NULL DEFAULT '{}',          -- Message-IDs; the search must find one of them
  reference_answer text,            -- the model answer the judge compares a draft with
  expected         jsonb,           -- anything else a test set expects
  note             text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (test_set, case_id)
);
-- Added 2 Nov 2026 (code review: WS2.3 shows Triage To and Cc, so the core and its cases do too); a no-op on new
-- databases.
ALTER TABLE n8n_workshop_mail.cases ADD COLUMN IF NOT EXISTS to_addrs text[] NOT NULL DEFAULT '{}';
ALTER TABLE n8n_workshop_mail.cases ADD COLUMN IF NOT EXISTS cc_addrs text[] NOT NULL DEFAULT '{}';

-- Correct: every exact measure that the case has is right, and the judge gave at least 4 of 5
-- (Workshop II). The bench sets `correct`, so the rule stays visible and changeable in n8n.
CREATE TABLE IF NOT EXISTS n8n_workshop_mail.results (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run          text NOT NULL CHECK (run <> ''),   -- the run's name from the form, else the execution id
  test_set     text NOT NULL,
  case_id      text NOT NULL,
  execution_id text,
  answer       text,          -- what the system returned: the draft, else the triage
  action       text,          -- the system's category or decision
  action_ok    boolean,       -- NULL when the case expects none
  sources      text[],        -- the Message-IDs the search returned
  source_ok    boolean,       -- an expected source among them; NULL when the case expects none
  checks_ok    boolean,       -- the fixed checks, e.g. no placeholder, the right recipient
  grade        smallint CHECK (grade BETWEEN 1 AND 5),   -- the judge's grade
  reason       text,          -- the judge's reasoning, or which check failed
  correct      boolean,
  error        text,          -- the system gave no answer, e.g. Langflow did not respond
  ms           integer CHECK (ms >= 0),
  detail       jsonb,         -- the rest, e.g. the raw triage
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS results_run_idx ON n8n_workshop_mail.results (run, test_set, case_id);

-- ---------------------------------------------------------------------------
-- Functions for n8n
-- ---------------------------------------------------------------------------

-- Approve a proposal. p_body replaces the text if the person edited it in the form.
CREATE OR REPLACE FUNCTION n8n_workshop_mail.approve(p_id bigint, p_by text, p_reason text DEFAULT NULL, p_body text DEFAULT NULL)
RETURNS n8n_workshop_mail.outbox
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r n8n_workshop_mail.outbox;
BEGIN
  IF p_by IS NULL OR btrim(p_by) = '' THEN
    RAISE EXCEPTION 'approve: name the person who approves';
  END IF;
  UPDATE n8n_workshop_mail.outbox
     SET status = 'approved', approved_by = btrim(p_by), approved_at = now(),
         reason = p_reason, body = coalesce(p_body, body)
   WHERE id = p_id AND status IN ('proposed', 'expired')
  RETURNING * INTO r;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approve: outbox % is not waiting for approval', p_id;
  END IF;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION n8n_workshop_mail.reject(p_id bigint, p_by text, p_reason text DEFAULT NULL)
RETURNS n8n_workshop_mail.outbox
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r n8n_workshop_mail.outbox;
BEGIN
  IF p_by IS NULL OR btrim(p_by) = '' THEN
    RAISE EXCEPTION 'reject: name the person who rejects';
  END IF;
  UPDATE n8n_workshop_mail.outbox
     SET status = 'rejected', rejected_by = btrim(p_by), rejected_at = now(), reason = p_reason
   WHERE id = p_id AND status IN ('proposed', 'expired')
  RETURNING * INTO r;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'reject: outbox % is not waiting for approval', p_id;
  END IF;
  RETURN r;
END $$;

-- Ask the container for a sync now ("Fetch now" button).
CREATE OR REPLACE FUNCTION n8n_workshop_mail.sync_now() RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_notify('n8n_workshop_mail_sync', json_build_object('action', 'sync')::text);
  RETURN 'sync requested';
END $$;

-- Course: ask the container to put test mail n into the inbox, tagged `test`.
CREATE OR REPLACE FUNCTION n8n_workshop_mail.deliver_test(n integer) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  IF n IS NULL OR n < 1 OR n > 999 THEN
    RAISE EXCEPTION 'deliver_test: n must be between 1 and 999, not %', n;
  END IF;
  PERFORM pg_notify('n8n_workshop_mail_sync', json_build_object('action', 'deliver_test', 'n', n)::text);
  RETURN format('test mail %s requested', n);
END $$;

-- ---------------------------------------------------------------------------
-- Rights
-- ---------------------------------------------------------------------------

REVOKE ALL ON SCHEMA n8n_workshop_mail FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA n8n_workshop_mail FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA n8n_workshop_mail FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA n8n_workshop_mail FROM PUBLIC;
GRANT USAGE ON SCHEMA n8n_workshop_mail TO n8n_workshop_mail_container, n8n_workshop_mail_n8n, n8n_workshop_mail_agent, n8n_workshop_mail_reply;

-- Mail container: writes the mailbox rows and moves outbox rows on after approval.
GRANT SELECT, INSERT, UPDATE, DELETE ON n8n_workshop_mail.messages TO n8n_workshop_mail_container;
GRANT SELECT ON n8n_workshop_mail.outbox TO n8n_workshop_mail_container;
GRANT UPDATE (status, message_id, raw, error) ON n8n_workshop_mail.outbox TO n8n_workshop_mail_container;
GRANT SELECT ON n8n_workshop_mail.changes TO n8n_workshop_mail_container;
GRANT UPDATE (status, error, done_at) ON n8n_workshop_mail.changes TO n8n_workshop_mail_container;
GRANT SELECT, UPDATE ON n8n_workshop_mail.sync_state TO n8n_workshop_mail_container;
GRANT SELECT, INSERT, UPDATE ON n8n_workshop_mail.seeded TO n8n_workshop_mail_container;
GRANT SELECT, INSERT, DELETE ON n8n_workshop_mail.chunks TO n8n_workshop_mail_container;   -- the documents only

-- n8n, fixed nodes: reads, proposes (content only), approves or rejects through the functions,
-- asks for changes (read, star, archive, label), claims mails and writes results.
GRANT SELECT ON n8n_workshop_mail.messages, n8n_workshop_mail.outbox, n8n_workshop_mail.calendar, n8n_workshop_mail.sync_state TO n8n_workshop_mail_n8n;
GRANT INSERT (mode, to_addrs, cc_addrs, subject, body, in_reply_to) ON n8n_workshop_mail.outbox TO n8n_workshop_mail_n8n;
GRANT SELECT ON n8n_workshop_mail.changes TO n8n_workshop_mail_n8n;
GRANT INSERT (message_id, action, label) ON n8n_workshop_mail.changes TO n8n_workshop_mail_n8n;
GRANT SELECT, INSERT, UPDATE, DELETE ON n8n_workshop_mail.processed TO n8n_workshop_mail_n8n;
GRANT SELECT, INSERT, UPDATE, DELETE ON n8n_workshop_mail.chunks TO n8n_workshop_mail_n8n;          -- not the documents
GRANT SELECT, INSERT, UPDATE, DELETE ON n8n_workshop_mail.cases, n8n_workshop_mail.results TO n8n_workshop_mail_n8n;
GRANT EXECUTE ON FUNCTION n8n_workshop_mail.approve(bigint, text, text, text), n8n_workshop_mail.reject(bigint, text, text),
                          n8n_workshop_mail.sync_now(), n8n_workshop_mail.deliver_test(integer), n8n_workshop_mail.in_quiet_period(date)
  TO n8n_workshop_mail_n8n;

-- Langflow, "Ask Mailbox" and the agent's SQL tool: reads everything, writes nothing.
GRANT SELECT ON n8n_workshop_mail.messages, n8n_workshop_mail.processed, n8n_workshop_mail.calendar,
                n8n_workshop_mail.chunks TO n8n_workshop_mail_agent;
GRANT EXECUTE ON FUNCTION n8n_workshop_mail.in_quiet_period(date) TO n8n_workshop_mail_agent;

-- Langflow, "Draft Reply": no mailbox rows at all. It gets the mail and its thread from n8n and
-- searches n8n_workshop_mail.chunks, which hides internal rows from it (read_external above).
-- The financial calendar is public.
GRANT SELECT ON n8n_workshop_mail.calendar, n8n_workshop_mail.chunks TO n8n_workshop_mail_reply;
GRANT EXECUTE ON FUNCTION n8n_workshop_mail.in_quiet_period(date) TO n8n_workshop_mail_reply;

COMMIT;
