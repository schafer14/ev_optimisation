package main

import (
	"bytes"
	"database/sql"
	"io"
	"log/slog"
	"net/http"
	"time"
)

type bodyRecorder struct {
	http.ResponseWriter
	status int
	body   bytes.Buffer
}

func (r *bodyRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *bodyRecorder) Write(b []byte) (int, error) {
	r.body.Write(b)
	return r.ResponseWriter.Write(b)
}

func requestLogMiddleware(db *sql.DB, logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestBody, _ := io.ReadAll(r.Body)
		r.Body = io.NopCloser(bytes.NewReader(requestBody))

		rec := &bodyRecorder{ResponseWriter: w, status: 200}
		start := time.Now()
		next.ServeHTTP(rec, r)
		solveMs := time.Since(start).Milliseconds()

		requestID, _ := r.Context().Value("request_id").(string)
		accountSlug, _ := r.Context().Value("account_id").(string)

		_, err := db.Exec(
			"INSERT INTO requests (id, account_slug, request_body, response_body, status, solve_time_ms) VALUES (?, ?, ?, ?, ?, ?)",
			requestID, accountSlug, string(requestBody), rec.body.String(), rec.status, solveMs,
		)
		if err != nil {
			logger.ErrorContext(r.Context(), "inserting request body", "err", err)
		}
	})
}

type RequestRecord struct {
	ID           string  `json:"id"`
	AccountSlug  string  `json:"account_slug"`
	RequestBody  string  `json:"request_body"`
	ResponseBody string  `json:"response_body"`
	Status       int     `json:"status"`
	SolveTimeMs  float64 `json:"solve_time_ms"`
	CreatedAt    string  `json:"created_at"`
}

func requestGet(db *sql.DB, id string) (RequestRecord, error) {
	var rec RequestRecord
	err := db.QueryRow(
		"SELECT id, account_slug, request_body, response_body, status, solve_time_ms, created_at FROM requests WHERE id = ?",
		id,
	).Scan(&rec.ID, &rec.AccountSlug, &rec.RequestBody, &rec.ResponseBody, &rec.Status, &rec.SolveTimeMs, &rec.CreatedAt)
	return rec, err
}
