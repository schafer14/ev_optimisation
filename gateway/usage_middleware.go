package main

import (
	"database/sql"
	"log/slog"
	"net/http"
)

func usageMiddleware(db *sql.DB, logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(w, r)

		if rec, ok := w.(*statusRecorder); ok && rec.status < 400 {
			accountSlug, _ := r.Context().Value("account_id").(string)
			_, err := db.Exec(
				"UPDATE usage SET count = count + 1, last_updated = datetime('now') WHERE account_slug = ?",
				accountSlug,
			)
			if err != nil {
				logger.ErrorContext(r.Context(), "updating usage", "err", err)
			}
		}
	})
}

type UsageRecord struct {
	AccountSlug string `json:"account_id"`
	Count       int64  `json:"count"`
	LastUpdated string `json:"last_updated"`
}

func usageGet(db *sql.DB, accountSlug string) (UsageRecord, error) {
	var rec UsageRecord
	err := db.QueryRow(
		"SELECT account_slug, count, last_updated FROM usage WHERE account_slug = ?",
		accountSlug,
	).Scan(&rec.AccountSlug, &rec.Count, &rec.LastUpdated)
	return rec, err
}

func usageList(db *sql.DB) ([]UsageRecord, error) {
	rows, err := db.Query("SELECT account_slug, count, last_updated FROM usage")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var records []UsageRecord
	for rows.Next() {
		var rec UsageRecord
		if err := rows.Scan(&rec.AccountSlug, &rec.Count, &rec.LastUpdated); err != nil {
			return nil, err
		}
		records = append(records, rec)
	}
	return records, rows.Err()
}
