-- +goose Up

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION trade_json(
    trade_record trades,
    account_record accounts,
    instrument_record instruments
)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT jsonb_build_object(
        'id', trade_record.id,
        'tradeId', trade_record.trade_id,
        'status', trade_record.status,
        'sessionDate', trade_record.session_date,

        'tradeNumber', trade_record.trade_number,

        'account', CASE

            WHEN account_record.id IS NULL THEN NULL
            ELSE jsonb_build_object(

                'id', account_record.id,
                'name', account_record.name,
                'propFirm', account_record.prop_firm,
                'accountType', account_record.account_type
            )

        END,

        'instrument', CASE
            WHEN instrument_record.symbol IS NULL THEN NULL
            ELSE jsonb_build_object(
                'symbol', instrument_record.symbol,
                'name', instrument_record.name,
                'tickSize', instrument_record.tick_size,
                'tickValue', instrument_record.tick_value
            )
        END,

        'direction', trade_record.direction,
        'contracts', trade_record.contracts,
        'entryTime', trade_record.entry_time,
        'exitTime', trade_record.exit_time,
        'entryPrice', trade_record.entry_price,
        'exitPrice', trade_record.exit_price,

        'initialStopPrice', trade_record.initial_stop_price,
        'initialStopReference', trade_record.initial_stop_reference,
        'plannedTargetPrice', trade_record.planned_target_price,
        'plannedTargetReference', trade_record.planned_target_reference,

        'setup', trade_record.setup,
        'primaryLocation', trade_record.primary_location,
        'secondaryLocation', trade_record.secondary_location,
        'trigger', trade_record.trigger,

        'fees', trade_record.fees,
        'grossPnl', trade_record.gross_pnl,
        'netPnl', trade_record.net_pnl,
        'plannedRiskPoints', trade_record.planned_risk_points,
        'plannedRiskUsd', trade_record.planned_risk_usd,
        'realizedR', trade_record.realized_r,

        'notes', trade_record.notes,
        'version', trade_record.version,
        'createdAt', trade_record.created_at,
        'updatedAt', trade_record.updated_at
    );
$$;

-- +goose StatementEnd

-- +goose Down

DROP FUNCTION IF EXISTS trade_json(trades, accounts, instruments);

