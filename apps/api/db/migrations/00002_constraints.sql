-- +goose Up

-- Multiple accounts may legitimately have no external account number.
ALTER TABLE accounts
    DROP CONSTRAINT IF EXISTS accounts_external_number_unique;

CREATE UNIQUE INDEX accounts_external_number_unique
    ON accounts (external_account_number)
    WHERE external_account_number IS NOT NULL;

-- Human-readable trade IDs may repeat across different accounts.
ALTER TABLE trades
    DROP CONSTRAINT IF EXISTS trades_trade_id_key;

-- Optimistic concurrency is represented by the version column.
ALTER TABLE trades
    ADD CONSTRAINT trades_version_positive
    CHECK (version > 0);

-- +goose Down

ALTER TABLE trades
    DROP CONSTRAINT IF EXISTS trades_version_positive;

ALTER TABLE trades

    ADD CONSTRAINT trades_trade_id_key UNIQUE (trade_id);


DROP INDEX IF EXISTS accounts_external_number_unique;

ALTER TABLE accounts

    ADD CONSTRAINT accounts_external_number_unique
    UNIQUE NULLS NOT DISTINCT (external_account_number);

