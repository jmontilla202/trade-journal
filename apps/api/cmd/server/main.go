package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/local/trade-journal/apps/api/internal/config"
	"github.com/local/trade-journal/apps/api/internal/database"
	"github.com/local/trade-journal/apps/api/internal/httpapi"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		runHealthcheck()
		return
	}

	logger := slog.New(
		slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
			Level: slog.LevelInfo,
		}),
	)

	cfg, err := config.Load()
	if err != nil {
		logger.Error("configuration error", "error", err)

		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stop()

	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("database connection failed", "error", err)
		os.Exit(1)

	}
	defer db.Close()

	api := httpapi.New(db, logger)

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErrors := make(chan error, 1)

	go func() {
		logger.Info(
			"API server started",
			"port", cfg.Port,
			"environment", cfg.Environment,
			"timezone", cfg.Timezone,
		)

		serverErrors <- server.ListenAndServe()
	}()

	select {

	case <-ctx.Done():
		logger.Info("shutdown signal received")

	case err := <-serverErrors:
		if err != nil && err != http.ErrServerClosed {
			logger.Error("server stopped unexpectedly", "error", err)
			os.Exit(1)
		}
	}

	shutdownCtx, cancel := context.WithTimeout(
		context.Background(),
		10*time.Second,
	)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}

	logger.Info("API server stopped")
}

func runHealthcheck() {
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	url := fmt.Sprintf(
		"http://127.0.0.1:%s/api/v1/health/live",

		port,
	)

	client := &http.Client{
		Timeout: 2 * time.Second,
	}

	response, err := client.Get(url)
	if err != nil {
		os.Exit(1)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		os.Exit(1)
	}
}
