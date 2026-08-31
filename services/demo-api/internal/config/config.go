package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

const (
	defaultPort            = 3000
	defaultShutdownTimeout = 15 * time.Second
)

type Config struct {
	Port            int
	Region          string
	Environment     string
	ShutdownTimeout time.Duration
}

func Load() (Config, error) {
	return load(os.Getenv)
}

func load(getenv func(string) string) (Config, error) {
	cfg := Config{
		Port:            defaultPort,
		Region:          valueOrDefault(getenv("AWS_REGION"), "local"),
		Environment:     valueOrDefault(getenv("APP_ENV"), "development"),
		ShutdownTimeout: defaultShutdownTimeout,
	}

	if raw := getenv("PORT"); raw != "" {
		port, err := strconv.Atoi(raw)
		if err != nil || port < 1 || port > 65535 {
			return Config{}, fmt.Errorf("PORT must be an integer from 1 to 65535")
		}
		cfg.Port = port
	}

	if raw := getenv("SHUTDOWN_TIMEOUT"); raw != "" {
		timeout, err := time.ParseDuration(raw)
		if err != nil || timeout <= 0 {
			return Config{}, fmt.Errorf("SHUTDOWN_TIMEOUT must be a positive duration")
		}
		cfg.ShutdownTimeout = timeout
	}

	return cfg, nil
}

func valueOrDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
