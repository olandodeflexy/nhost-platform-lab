package config

import (
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	cfg, err := load(func(string) string { return "" })
	if err != nil {
		t.Fatalf("load defaults: %v", err)
	}

	if cfg.Port != 3000 {
		t.Fatalf("Port = %d, want 3000", cfg.Port)
	}
	if cfg.Region != "local" {
		t.Fatalf("Region = %q, want local", cfg.Region)
	}
	if cfg.Environment != "development" {
		t.Fatalf("Environment = %q, want development", cfg.Environment)
	}
	if cfg.ShutdownTimeout != 15*time.Second {
		t.Fatalf("ShutdownTimeout = %s, want 15s", cfg.ShutdownTimeout)
	}
}

func TestLoadOverrides(t *testing.T) {
	values := map[string]string{
		"PORT":             "8080",
		"AWS_REGION":       "eu-west-1",
		"APP_ENV":          "nonprod",
		"SHUTDOWN_TIMEOUT": "20s",
	}

	cfg, err := load(func(key string) string { return values[key] })
	if err != nil {
		t.Fatalf("load overrides: %v", err)
	}

	if cfg.Port != 8080 || cfg.Region != "eu-west-1" || cfg.Environment != "nonprod" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
	if cfg.ShutdownTimeout != 20*time.Second {
		t.Fatalf("ShutdownTimeout = %s, want 20s", cfg.ShutdownTimeout)
	}
}

func TestLoadRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name   string
		values map[string]string
	}{
		{name: "nonnumeric port", values: map[string]string{"PORT": "nope"}},
		{name: "port too high", values: map[string]string{"PORT": "70000"}},
		{name: "invalid timeout", values: map[string]string{"SHUTDOWN_TIMEOUT": "soon"}},
		{name: "zero timeout", values: map[string]string{"SHUTDOWN_TIMEOUT": "0s"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := load(func(key string) string { return tc.values[key] })
			if err == nil {
				t.Fatal("load returned nil error")
			}
		})
	}
}
