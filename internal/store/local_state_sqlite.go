package store

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

type LocalStateDB struct {
	db *sql.DB
}

type PersistedSessionState struct {
	Ended   bool
	Managed bool
}

func OpenLocalStateDB(path string) (*LocalStateDB, error) {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return nil, nil
	}

	if err := os.MkdirAll(filepath.Dir(trimmed), 0o755); err != nil {
		return nil, fmt.Errorf("create state db directory: %w", err)
	}

	rawDB, err := sql.Open("sqlite", trimmed)
	if err != nil {
		return nil, fmt.Errorf("open state db: %w", err)
	}
	rawDB.SetMaxOpenConns(1)

	db := &LocalStateDB{db: rawDB}
	if err := db.exec("PRAGMA busy_timeout = 5000;"); err != nil {
		_ = rawDB.Close()
		return nil, err
	}
	if err := db.exec(`
CREATE TABLE IF NOT EXISTS session_local_state (
	thread_id TEXT PRIMARY KEY,
	ended INTEGER NOT NULL DEFAULT 1,
	managed INTEGER NOT NULL DEFAULT 0,
	updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);`); err != nil {
		_ = rawDB.Close()
		return nil, err
	}
	if err := db.addColumnIfMissing("ALTER TABLE session_local_state ADD COLUMN managed INTEGER NOT NULL DEFAULT 0;"); err != nil {
		_ = rawDB.Close()
		return nil, err
	}

	return db, nil
}

func (db *LocalStateDB) LoadSessionStates() (map[string]PersistedSessionState, error) {
	if db == nil {
		return map[string]PersistedSessionState{}, nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	rows, err := db.db.QueryContext(ctx, "SELECT thread_id, ended, managed FROM session_local_state;")
	if err != nil {
		return nil, fmt.Errorf("query session local state: %w", err)
	}
	defer rows.Close()

	result := make(map[string]PersistedSessionState)
	for rows.Next() {
		var threadID string
		var ended int
		var managed int
		if err := rows.Scan(&threadID, &ended, &managed); err != nil {
			return nil, fmt.Errorf("scan session local state row: %w", err)
		}
		threadID = strings.TrimSpace(threadID)
		if threadID == "" {
			continue
		}
		result[threadID] = PersistedSessionState{
			Ended:   ended != 0,
			Managed: managed != 0,
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate session local state rows: %w", err)
	}

	return result, nil
}

func (db *LocalStateDB) SaveSessionState(threadID string, state PersistedSessionState) error {
	if db == nil || strings.TrimSpace(threadID) == "" {
		return nil
	}

	if !state.Ended && !state.Managed {
		return db.exec(fmt.Sprintf(
			"DELETE FROM session_local_state WHERE thread_id = %s;",
			sqlString(threadID),
		))
	}

	return db.exec(fmt.Sprintf(`
INSERT INTO session_local_state (thread_id, ended, managed, updated_at)
VALUES (%s, %d, %d, unixepoch())
ON CONFLICT(thread_id) DO UPDATE SET
	ended = excluded.ended,
	managed = excluded.managed,
	updated_at = unixepoch();`,
		sqlString(threadID),
		boolToInt(state.Ended),
		boolToInt(state.Managed),
	))
}

func (db *LocalStateDB) exec(sqlText string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if _, err := db.db.ExecContext(ctx, sqlText); err != nil {
		return fmt.Errorf("execute state db sql: %w", err)
	}
	return nil
}

func (db *LocalStateDB) addColumnIfMissing(sqlText string) error {
	if err := db.exec(sqlText); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	return nil
}

func sqlString(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}
