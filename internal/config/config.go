package config

import (
	"os"
	"path/filepath"
	"time"
)

type Config struct {
	ListenAddr      string
	CodexPath       string
	RefreshInterval time.Duration
	StateDBPath     string
}

func Load() Config {
	return Config{
		ListenAddr:      getenv("CODEXFLOW_LISTEN_ADDR", "127.0.0.1:4318"),
		CodexPath:       getenv("CODEXFLOW_CODEX_PATH", "codex"),
		RefreshInterval: getDurationEnv("CODEXFLOW_REFRESH_INTERVAL", 12*time.Second),
		StateDBPath:     getenv("CODEXFLOW_STATE_DB_PATH", defaultStateDBPath()),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getDurationEnv(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	parsed, err := time.ParseDuration(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

func defaultStateDBPath() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "./codexflow-state.db"
	}
	return filepath.Join(home, ".codexflow", "state.db")
}
