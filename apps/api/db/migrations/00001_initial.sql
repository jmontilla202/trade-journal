-- +goose Up

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE trade_status AS ENUM (
    'DRAFT',
    'OPEN',
    'CLOSED',
    'REVIEWED'
);

CREATE TYPE trade_direction AS ENUM (
    'LONG',
    'SHORT'
);

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    external_account_number TEXT,
    prop_firm TEXT,
    account_type TEXT NOT NULL,
    account_size NUMERIC(14, 2),
    active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT accounts_name_not_blank
        CHECK (length(trim(name)) > 0),

    CONSTRAINT accounts_external_number_unique

        UNIQUE NULLS NOT DISTINCT (external_account_number)

);

CREATE TABLE instruments (
    symbol TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    exchange TEXT NOT NULL,
    tick_size NUMERIC(12, 6) NOT NULL,
    tick_value NUMERIC(12, 6) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'USD',

    active BOOLEAN NOT NULL DEFAULT TRUE,


    CONSTRAINT instruments_tick_size_positive
        CHECK (tick_size > 0),

    CONSTRAINT instruments_tick_value_positive
        CHECK (tick_value > 0)
);


CREATE TABLE trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_id TEXT UNIQUE,
    account_id UUID REFERENCES accounts(id),
    instrument_symbol TEXT REFERENCES instruments(symbol),

    status trade_status NOT NULL DEFAULT 'DRAFT',
    session_date DATE NOT NULL,
    trade_number INTEGER,
    direction trade_direction,
    contracts INTEGER,

    entry_time TIMESTAMPTZ,
    exit_time TIMESTAMPTZ,
    entry_price NUMERIC(14, 4),
    exit_price NUMERIC(14, 4),

    initial_stop_price NUMERIC(14, 4),
    initial_stop_reference TEXT,
    planned_target_price NUMERIC(14, 4),
    planned_target_reference TEXT,

    setup TEXT,

    primary_location TEXT,
    secondary_location TEXT,
    trigger TEXT,

    fees NUMERIC(14, 2) NOT NULL DEFAULT 0,
    gross_pnl NUMERIC(14, 2),

    net_pnl NUMERIC(14, 2),
    planned_risk_points NUMERIC(14, 4),
    planned_risk_usd NUMERIC(14, 2),
    realized_r NUMERIC(14, 6),

    notes TEXT,

    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT trades_contracts_positive
        CHECK (contracts IS NULL OR contracts > 0),

    CONSTRAINT trades_fees_nonnegative
        CHECK (fees >= 0),

    CONSTRAINT trades_trade_number_positive
        CHECK (trade_number IS NULL OR trade_number > 0),

    CONSTRAINT trades_exit_after_entry
        CHECK (
            exit_time IS NULL
            OR entry_time IS NULL
            OR exit_time >= entry_time
        )
);

CREATE UNIQUE INDEX trades_session_trade_number_unique
    ON trades (account_id, session_date, trade_number)
    WHERE trade_number IS NOT NULL;

CREATE INDEX trades_session_date_idx
    ON trades (session_date DESC);


CREATE INDEX trades_account_session_idx
    ON trades (account_id, session_date DESC);

CREATE INDEX trades_status_idx
    ON trades (status);


INSERT INTO instruments (
    symbol,
    name,
    exchange,
    tick_size,
    tick_value
)
VALUES
    ('ES',  'E-mini S&P 500',       'CME', 0.25, 12.50),
    ('MES', 'Micro E-mini S&P 500', 'CME', 0.25, 1.25),
    ('NQ',  'E-mini Nasdaq-100',    'CME', 0.25, 5.00),
    ('MNQ', 'Micro E-mini Nasdaq',  'CME', 0.25, 0.50)
ON CONFLICT (symbol) DO UPDATE
SET
    name = EXCLUDED.name,
    exchange = EXCLUDED.exchange,
    tick_size = EXCLUDED.tick_size,
    tick_value = EXCLUDED.tick_value;


INSERT INTO accounts (
    name,

    prop_firm,
    account_type,
    account_size
)
SELECT
    'Local Simulation',
    NULL,
    'SIMULATION',
    50000
WHERE NOT EXISTS (
    SELECT 1
    FROM accounts
    WHERE name = 'Local Simulation'
);

-- +goose Down

DROP TABLE IF EXISTS trades;
DROP TABLE IF EXISTS instruments;
DROP TABLE IF EXISTS accounts;
DROP TYPE IF EXISTS trade_direction;
DROP TYPE IF EXISTS trade_status;

