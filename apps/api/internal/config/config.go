package config

import (
	"fmt"
	"os"
)

type Config struct {
	Environment string
	Port        string
	Timezone    string
	DatabaseURL string
}

func Load() (Config, error) {
	cfg := Config{
		Environment: envOrDefault("APP_ENV", "development"),
		Port:        envOrDefault("APP_PORT", "8080"),
		Timezone:    envOrDefault("APP_TIMEZONE", "America/New_York"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}

	return cfg, nil
}

func envOrDefault(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}
