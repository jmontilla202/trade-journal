package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Server struct {
	db     *pgxpool.Pool
	logger *slog.Logger
	router chi.Router
}

type tradeInput struct {
	SessionDate string  `json:"sessionDate"`
	AccountID   *string `json:"accountId"`
	Instrument  *string `json:"instrument"`

	Direction *string `json:"direction"`
	Contracts *int    `json:"contracts"`

	EntryTime            *time.Time `json:"entryTime"`
	EntryPrice           *float64   `json:"entryPrice"`
	InitialStopPrice     *float64   `json:"initialStopPrice"`
	InitialStopReference *string    `json:"initialStopReference"`

	PlannedTargetPrice     *float64 `json:"plannedTargetPrice"`
	PlannedTargetReference *string  `json:"plannedTargetReference"`
	Setup                  *string  `json:"setup"`
	PrimaryLocation        *string  `json:"primaryLocation"`
	SecondaryLocation      *string  `json:"secondaryLocation"`
	Trigger                *string  `json:"trigger"`
	Notes                  *string  `json:"notes"`
}

type closeTradeInput struct {
	ExitTime  time.Time `json:"exitTime"`
	ExitPrice float64   `json:"exitPrice"`
	Fees      float64   `json:"fees"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func New(db *pgxpool.Pool, logger *slog.Logger) *Server {
	server := &Server{
		db:     db,
		logger: logger,
	}

	router := chi.NewRouter()

	router.Use(middleware.RequestID)
	router.Use(middleware.RealIP)
	router.Use(middleware.Recoverer)
	router.Use(server.loggingMiddleware)
	router.Use(middleware.Timeout(15 * time.Second))

	router.Get("/api/v1/health/live", server.live)

	router.Get("/api/v1/health/ready", server.ready)
	router.Handle("/metrics", promhttp.Handler())

	router.Route("/api/v1", func(router chi.Router) {
		router.Get("/accounts", server.listAccounts)
		router.Get("/instruments", server.listInstruments)

		router.Route("/trades", func(router chi.Router) {
			router.Get("/", server.listTrades)
			router.Post("/", server.createTrade)

			router.Route("/{tradeID}", func(router chi.Router) {
				router.Get("/", server.getTradeHandler)
				router.Put("/", server.updateDraft)
				router.Post("/open", server.openTrade)
				router.Post("/close", server.closeTrade)
			})
		})
	})

	server.router = router

	return server
}

func (s *Server) Handler() http.Handler {
	return s.router
}

func (s *Server) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{

		"status": "alive",
	})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := s.db.Ping(ctx); err != nil {
		s.logger.Error("readiness database check failed", "error", err)

		writeError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ready",
	})
}

func (s *Server) listAccounts(w http.ResponseWriter, r *http.Request) {
	const query = `
		SELECT COALESCE(
			jsonb_agg(
				jsonb_build_object(
					'id', id,
					'name', name,
					'externalAccountNumber', external_account_number,
					'propFirm', prop_firm,
					'accountType', account_type,
					'accountSize', account_size,
					'active', active
				)

				ORDER BY name
			),
			'[]'::jsonb
		)
		FROM accounts
		WHERE active = TRUE
	`

	s.writeJSONQuery(w, r, query)
}

func (s *Server) listInstruments(w http.ResponseWriter, r *http.Request) {
	const query = `
		SELECT COALESCE(
			jsonb_agg(
				jsonb_build_object(
					'symbol', symbol,
					'name', name,
					'exchange', exchange,
					'tickSize', tick_size,
					'tickValue', tick_value,
					'currency', currency
				)
				ORDER BY symbol
			),
			'[]'::jsonb
		)
		FROM instruments
		WHERE active = TRUE

	`

	s.writeJSONQuery(w, r, query)
}

func (s *Server) listTrades(w http.ResponseWriter, r *http.Request) {
	limit := 100

	if rawLimit := r.URL.Query().Get("limit"); rawLimit != "" {
		parsed, err := strconv.Atoi(rawLimit)
		if err != nil || parsed < 1 || parsed > 500 {
			writeError(w, http.StatusBadRequest, "limit must be between 1 and 500")
			return
		}

		limit = parsed

	}

	const query = `
		SELECT COALESCE(
			jsonb_agg(result.trade ORDER BY result.created_at DESC),
			'[]'::jsonb

		)
		FROM (
			SELECT
				trade_json(t, a, i) AS trade,
				t.created_at
			FROM trades t
			LEFT JOIN accounts a ON a.id = t.account_id
			LEFT JOIN instruments i ON i.symbol = t.instrument_symbol
			ORDER BY t.created_at DESC
			LIMIT $1
		) result
	`

	s.writeJSONQuery(w, r, query, limit)
}

func (s *Server) getTradeHandler(w http.ResponseWriter, r *http.Request) {
	trade, err := s.getTrade(r.Context(), chi.URLParam(r, "tradeID"))
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "trade not found")
		return
	}

	if err != nil {
		s.internalError(w, "get trade", err)
		return
	}

	writeRawJSON(w, http.StatusOK, trade)
}

func (s *Server) createTrade(w http.ResponseWriter, r *http.Request) {
	var input tradeInput

	if err := decodeJSON(r, &input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	sessionDate, err := parseSessionDate(input.SessionDate)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	const query = `
		INSERT INTO trades (
			session_date,
			account_id,
			instrument_symbol,
			direction,
			contracts,
			entry_time,
			entry_price,
			initial_stop_price,
			initial_stop_reference,
			planned_target_price,
			planned_target_reference,
			setup,
			primary_location,
			secondary_location,

			trigger,
			notes
		)

		VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8,
			$9, $10, $11, $12, $13, $14, $15, $16
		)
		RETURNING id::text
	`

	var id string

	err = s.db.QueryRow(
		r.Context(),
		query,
		sessionDate,
		input.AccountID,
		input.Instrument,
		input.Direction,
		input.Contracts,
		input.EntryTime,
		input.EntryPrice,
		input.InitialStopPrice,
		input.InitialStopReference,
		input.PlannedTargetPrice,
		input.PlannedTargetReference,
		input.Setup,
		input.PrimaryLocation,
		input.SecondaryLocation,
		input.Trigger,
		input.Notes,
	).Scan(&id)

	if err != nil {
		s.internalError(w, "create trade", err)

		return
	}

	trade, err := s.getTrade(r.Context(), id)
	if err != nil {
		s.internalError(w, "load created trade", err)
		return
	}

	writeRawJSON(w, http.StatusCreated, trade)
}

func (s *Server) updateDraft(w http.ResponseWriter, r *http.Request) {
	var input tradeInput

	if err := decodeJSON(r, &input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	sessionDate, err := parseSessionDate(input.SessionDate)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	const query = `
		UPDATE trades
		SET
			session_date = $2,
			account_id = $3,
			instrument_symbol = $4,

			direction = $5,
			contracts = $6,
			entry_time = $7,
			entry_price = $8,
			initial_stop_price = $9,
			initial_stop_reference = $10,
			planned_target_price = $11,

			planned_target_reference = $12,

			setup = $13,
			primary_location = $14,
			secondary_location = $15,
			trigger = $16,

			notes = $17,
			version = version + 1,

			updated_at = NOW()
		WHERE id = $1
		  AND status = 'DRAFT'
		RETURNING id::text
	`

	var id string

	err = s.db.QueryRow(
		r.Context(),
		query,
		chi.URLParam(r, "tradeID"),
		sessionDate,
		input.AccountID,
		input.Instrument,
		input.Direction,
		input.Contracts,
		input.EntryTime,
		input.EntryPrice,
		input.InitialStopPrice,
		input.InitialStopReference,
		input.PlannedTargetPrice,
		input.PlannedTargetReference,
		input.Setup,
		input.PrimaryLocation,
		input.SecondaryLocation,
		input.Trigger,
		input.Notes,
	).Scan(&id)

	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusConflict, "trade is not a draft or does not exist")
		return
	}

	if err != nil {

		s.internalError(w, "update draft", err)
		return
	}

	trade, err := s.getTrade(r.Context(), id)
	if err != nil {
		s.internalError(w, "load updated trade", err)
		return

	}

	writeRawJSON(w, http.StatusOK, trade)
}

func (s *Server) openTrade(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id := chi.URLParam(r, "tradeID")

	tx, err := s.db.Begin(ctx)
	if err != nil {
		s.internalError(w, "begin open-trade transaction", err)
		return
	}

	defer func() {
		_ = tx.Rollback(ctx)
	}()

	const loadQuery = `
		SELECT
			account_id::text,
			session_date
		FROM trades

		WHERE id = $1

		  AND status = 'DRAFT'
		  AND account_id IS NOT NULL
		  AND instrument_symbol IS NOT NULL
		  AND direction IS NOT NULL
		  AND contracts IS NOT NULL
		  AND entry_time IS NOT NULL
		  AND entry_price IS NOT NULL
		FOR UPDATE
	`

	var accountID string
	var sessionDate time.Time

	err = tx.QueryRow(ctx, loadQuery, id).Scan(&accountID, &sessionDate)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(
			w,
			http.StatusConflict,
			"draft is missing required fields or is not in DRAFT status",
		)

		return
	}

	if err != nil {
		s.internalError(w, "load draft for opening", err)
		return
	}

	lockKey := accountID + ":" + sessionDate.Format("2006-01-02")

	if _, err := tx.Exec(

		ctx,
		`SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
		lockKey,
	); err != nil {

		s.internalError(w, "lock daily trade sequence", err)
		return
	}

	var tradeNumber int

	err = tx.QueryRow(
		ctx,
		`
			SELECT COALESCE(MAX(trade_number), 0) + 1
			FROM trades
			WHERE account_id = $1
			  AND session_date = $2
		`,
		accountID,
		sessionDate,
	).Scan(&tradeNumber)

	if err != nil {
		s.internalError(w, "calculate trade number", err)
		return
	}

	humanTradeID := fmt.Sprintf(
		"%s-%02d",
		sessionDate.Format("2006-01-02"),

		tradeNumber,
	)

	commandTag, err := tx.Exec(
		ctx,
		`
			UPDATE trades
			SET
				status = 'OPEN',
				trade_number = $2,

				trade_id = $3,
				version = version + 1,
				updated_at = NOW()
			WHERE id = $1
			  AND status = 'DRAFT'
		`,
		id,
		tradeNumber,
		humanTradeID,
	)

	if err != nil {
		s.internalError(w, "open trade", err)
		return
	}

	if commandTag.RowsAffected() != 1 {
		writeError(w, http.StatusConflict, "trade could not be opened")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		s.internalError(w, "commit open trade", err)
		return
	}

	trade, err := s.getTrade(ctx, id)

	if err != nil {
		s.internalError(w, "load opened trade", err)
		return
	}

	writeRawJSON(w, http.StatusOK, trade)
}

func (s *Server) closeTrade(w http.ResponseWriter, r *http.Request) {
	var input closeTradeInput

	if err := decodeJSON(r, &input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	if input.ExitTime.IsZero() {
		writeError(w, http.StatusBadRequest, "exitTime is required")
		return
	}

	if input.ExitPrice <= 0 {
		writeError(w, http.StatusBadRequest, "exitPrice must be greater than zero")
		return

	}

	if input.Fees < 0 {
		writeError(w, http.StatusBadRequest, "fees cannot be negative")
		return
	}

	const query = `
		WITH calculation AS (
			SELECT
				t.id,
				CASE t.direction

					WHEN 'LONG' THEN
						($3::numeric - t.entry_price)
					WHEN 'SHORT' THEN
						(t.entry_price - $3::numeric)
				END
				/ i.tick_size
				* i.tick_value
				* t.contracts AS gross_pnl,

				CASE
					WHEN t.initial_stop_price IS NULL THEN NULL
					ELSE ABS(t.entry_price - t.initial_stop_price)
				END AS risk_points,

				CASE
					WHEN t.initial_stop_price IS NULL THEN NULL
					ELSE
						ABS(t.entry_price - t.initial_stop_price)
						/ i.tick_size
						* i.tick_value
						* t.contracts
				END AS risk_usd
			FROM trades t
			JOIN instruments i
			  ON i.symbol = t.instrument_symbol
			WHERE t.id = $1
			  AND t.status = 'OPEN'

		)
		UPDATE trades t
		SET
			status = 'CLOSED',
			exit_time = $2,
			exit_price = $3,
			fees = ROUND($4::numeric, 2),
			gross_pnl = ROUND(c.gross_pnl, 2),
			net_pnl = ROUND(c.gross_pnl - $4::numeric, 2),
			planned_risk_points = c.risk_points,
			planned_risk_usd = ROUND(c.risk_usd, 2),
			realized_r = CASE
				WHEN c.risk_usd IS NULL OR c.risk_usd = 0 THEN NULL

				ELSE ROUND(
					(c.gross_pnl - $4::numeric) / c.risk_usd,
					6
				)
			END,
			version = version + 1,

			updated_at = NOW()
		FROM calculation c
		WHERE t.id = c.id
		RETURNING t.id::text

	`

	var id string

	err := s.db.QueryRow(
		r.Context(),
		query,

		chi.URLParam(r, "tradeID"),
		input.ExitTime,

		input.ExitPrice,
		input.Fees,
	).Scan(&id)

	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusConflict, "trade is not open or does not exist")
		return
	}

	if err != nil {
		s.internalError(w, "close trade", err)
		return
	}

	trade, err := s.getTrade(r.Context(), id)
	if err != nil {
		s.internalError(w, "load closed trade", err)
		return
	}

	writeRawJSON(w, http.StatusOK, trade)
}

func (s *Server) getTrade(ctx context.Context, id string) ([]byte, error) {
	const query = `

		SELECT trade_json(t, a, i)
		FROM trades t
		LEFT JOIN accounts a ON a.id = t.account_id
		LEFT JOIN instruments i ON i.symbol = t.instrument_symbol
		WHERE t.id = $1
	`

	var result []byte
	err := s.db.QueryRow(ctx, query, id).Scan(&result)

	return result, err
}

func (s *Server) writeJSONQuery(
	w http.ResponseWriter,
	r *http.Request,
	query string,
	args ...any,
) {
	var result []byte

	if err := s.db.QueryRow(r.Context(), query, args...).Scan(&result); err != nil {
		s.internalError(w, "execute JSON query", err)
		return
	}

	writeRawJSON(w, http.StatusOK, result)
}

func (s *Server) internalError(w http.ResponseWriter, operation string, err error) {
	s.logger.Error(
		"request failed",
		"operation", operation,
		"error", err,
	)

	writeError(w, http.StatusInternalServerError, "internal server error")
}

func (s *Server) loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		wrapped := middleware.NewWrapResponseWriter(w, r.ProtoMajor)

		next.ServeHTTP(wrapped, r)

		s.logger.Info(
			"http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", wrapped.Status(),
			"bytes", wrapped.BytesWritten(),
			"duration_ms", time.Since(started).Milliseconds(),
			"request_id", middleware.GetReqID(r.Context()),
		)
	})
}

func parseSessionDate(value string) (time.Time, error) {

	if value == "" {
		return time.Time{}, fmt.Errorf("sessionDate is required")
	}

	date, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, fmt.Errorf("sessionDate must use YYYY-MM-DD format")

	}

	return date, nil
}

func decodeJSON(r *http.Request, destination any) error {
	decoder := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	decoder.DisallowUnknownFields()

	if err := decoder.Decode(destination); err != nil {
		return fmt.Errorf("invalid request body: %w", err)
	}

	return nil
}

func writeError(w http.ResponseWriter, status int, message string) {

	writeJSON(w, status, errorResponse{Error: message})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	_ = json.NewEncoder(w).Encode(value)
}

func writeRawJSON(w http.ResponseWriter, status int, value []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	_, _ = w.Write(value)
}
