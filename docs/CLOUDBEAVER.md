# Using CloudBeaver — the SQL workbench in your browser

CloudBeaver (<http://localhost:8978>) is a database client that runs in the
browser. It is the comfortable way to look at the class database and to write
SQL against it.

> **Two different logins are involved — that is the one confusing thing here.**
> First you log in to **CloudBeaver itself** (`student` / `Kingo2026!`), and
> once, on first use, you give it the **database's** password
> (`student` / `kingo2026`). Different passwords, on purpose.

## 1. Log in to CloudBeaver

Open <http://localhost:8978>. The first page says **"No Connections. Use the
top menu to setup connection to your database."** — that is normal, it just
means you are not logged in yet.

1. Click the **gear icon** in the top-right corner.
2. Choose **Login**.
3. User name **`student`**, password **`Kingo2026!`**, then **LOGIN**.

Your name now appears in the blue bar, and the left panel shows **Shared →
Classroom (PostgreSQL)**. (The connection is pre-made for you — you never have
to create one.)

## 2. Give it the database password — once

Click **Classroom (PostgreSQL)**. CloudBeaver asks for the database
credentials. If it does not ask, click the **≡ menu** next to the connection →
**Manage → Edit Connection**, and fill in the **AUTHENTICATION** box:

| Field | Value |
|---|---|
| Authentication | Username/password |
| User name | `student` |
| User password | `kingo2026` |
| Save credentials … | **tick it** |

Then **TEST** (should say the connection works) and **SAVE**. You only do this
once — CloudBeaver remembers it from then on.

## 3. Look at the data

Expand **Classroom (PostgreSQL) → classroom → Schemas → public → Tables**.
The class sample data is there: `products`, `customers`, `orders`. Double-click
a table to see its rows.

For your own SQL, click the **SQL** icon in the blue bar (with the connection
selected) and type away, for example:

```sql
SELECT p.category, sum(o.quantity) AS units FROM orders o JOIN products p USING (product_id) GROUP BY 1 ORDER BY 2 DESC;
```

Run it with **Ctrl+Enter** (⌘+Enter on a Mac).

## Which database should I pick?

The stack runs **one PostgreSQL server with four databases** inside it:

| Database | What it is |
|---|---|
| `classroom` | **yours** — the class data, this is the one you work in |
| `langflow` | Langflow's own storage (your flows live here) |
| `n8n` | n8n's own storage (your workflows) |
| `metabase` | Metabase's own storage (dashboards, settings) |

You can see all four, because they share one login. **Only work in
`classroom`.** Writing into the other three can break the app that owns them.

## If something looks wrong

- **"No Connections", and no `+` icon in the blue bar** → you are not logged in.
  Go back to step 1; an anonymous visitor sees neither the connection nor the
  button to make one.
- **It asks for the database password every time** → the "Save credentials"
  box in step 2 was not ticked. Repeat step 2.
- **The connection fails to open** → check that the stack is up
  (`./kingo status`). If the setup moved PostgreSQL to another port on your
  laptop, that does not matter here: CloudBeaver talks to the database *inside*
  the stack, always on `postgres:5432`.
- **You want to start over** → `≡ menu → Manage → Edit Connection` lets you
  correct anything. The connection cannot be lost: it is re-created from the
  class files every time the stack starts.
