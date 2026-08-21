-- Runs once, when the postgres named volume is first created (on the first
-- `kingo up`). Creates the per-service databases plus a small sample dataset
-- in the `classroom` database so Metabase / CloudBeaver / Jupyter have
-- something to query on day one.

CREATE DATABASE langflow;
CREATE DATABASE n8n;
CREATE DATABASE metabase;

\connect classroom

SELECT setseed(0.42);

CREATE TABLE products (
    product_id   serial PRIMARY KEY,
    name         text NOT NULL,
    category     text NOT NULL,
    unit_price   numeric(8,2) NOT NULL
);

INSERT INTO products (name, category, unit_price) VALUES
    ('Espresso',        'Coffee',   3.00),
    ('Americano',       'Coffee',   3.50),
    ('Cappuccino',      'Coffee',   4.20),
    ('Latte',           'Coffee',   4.50),
    ('Green Tea',       'Tea',      3.20),
    ('Black Tea',       'Tea',      3.00),
    ('Croissant',       'Bakery',   2.80),
    ('Bagel',           'Bakery',   2.50),
    ('Cheesecake',      'Bakery',   5.50),
    ('Orange Juice',    'Cold',     4.00);

CREATE TABLE customers (
    customer_id  serial PRIMARY KEY,
    name         text NOT NULL,
    city         text NOT NULL,
    signup_date  date NOT NULL
);

INSERT INTO customers (name, city, signup_date)
SELECT
    'Customer ' || i,
    (ARRAY['Seoul','Suwon','Busan','Daejeon','Incheon'])[1 + floor(random()*5)::int],
    DATE '2025-01-01' + (random()*365)::int
FROM generate_series(1, 50) AS i;

CREATE TABLE orders (
    order_id     serial PRIMARY KEY,
    customer_id  int NOT NULL REFERENCES customers,
    product_id   int NOT NULL REFERENCES products,
    quantity     int NOT NULL,
    order_ts     timestamp NOT NULL
);

INSERT INTO orders (customer_id, product_id, quantity, order_ts)
SELECT
    1 + floor(random()*50)::int,
    1 + floor(random()*10)::int,
    1 + floor(random()*4)::int,
    TIMESTAMP '2025-06-01 08:00' + (random()*440) * INTERVAL '1 hour'
FROM generate_series(1, 500);
