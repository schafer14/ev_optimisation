package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"log/slog"
	"net/http"
)

func hashKey(key string) string {
	h := sha256.Sum256([]byte(key))
	return hex.EncodeToString(h[:])
}

func apiKeyMiddleware(db *sql.DB, logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("X-API-Key")
		if key == "" {
			http.Error(w, `{"error": "missing API key"}`, http.StatusUnauthorized)
			return
		}

		var accountSlug string
		err := db.QueryRow(
			"SELECT account_slug FROM api_keys WHERE hashed_key = ?",
			hashKey(key),
		).Scan(&accountSlug)

		if err == sql.ErrNoRows {
			http.Error(w, `{"error": "invalid API key"}`, http.StatusUnauthorized)
			return
		}
		if err != nil {
			logger.ErrorContext(r.Context(), "checking api key", "err", err)
			http.Error(w, `{"error": "internal error"}`, http.StatusInternalServerError)
			return
		}

		ctx := context.WithValue(r.Context(), "account_id", accountSlug)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
