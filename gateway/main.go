package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

func main() {
	os.Exit(Main())
}

var (
	addr       = flag.String("addr", ":7777", "listen address")
	solverAddr = flag.String("solver-addr", "http://localhost:8080", "solver address")
	dbURI      = flag.String("db", "optimsation.db", "database file")

	adminAccountsFlag = flag.String("admin-accounts", "admin", "a comma separated list of account names that can access the admin API")
)

func Main() int {
	flag.Parse()

	logger := newLogger(LogFormatPretty, slog.LevelDebug)

	logger.Info("config set", "addr", *addr)
	logger.Info("config set", "solver-addr", *solverAddr)
	logger.Info("config set", "db", *dbURI)

	db, err := sql.Open("sqlite", *dbURI)
	if err != nil {
		logger.Error("connecting to db", "err", err)
		return 1
	}

	rl := NewRateLimiter(100, time.Minute) // 100 requests per minute
	solver := NewSolver(*solverAddr)

	r := http.NewServeMux()
	r.HandleFunc("GET /health", checkHealth(solver))
	r.HandleFunc("GET /ping", ping())

	// API router
	{
		protected := http.NewServeMux()
		protected.Handle("POST /v1-alpha/plan", usageMiddleware(db, logger, requestLogMiddleware(db, logger, solver)))
		protected.HandleFunc("GET /v1-alpha/usage", checkUsage(db, logger))

		var handler http.Handler = protected

		handler = rateLimitMiddleware(rl, handler)
		handler = loggingMiddleware(logger, handler)
		handler = apiKeyMiddleware(db, logger, handler)
		handler = requestIDMiddleware(handler)
		handler = panicMiddleware(logger, handler)

		r.Handle("/api/", http.StripPrefix("/api", handler))
	}

	//  Admin router
	{
		protected := http.NewServeMux()
		protected.Handle("GET /usage", listUsage(db, logger))
		protected.Handle("GET /request/{RequestID}", requestDetails(db, logger))

		var handler http.Handler = protected

		adminAccounts := strings.Split(*adminAccountsFlag, ",")

		handler = allowedAccounts(adminAccounts, handler)
		handler = loggingMiddleware(logger, handler)
		handler = apiKeyMiddleware(db, logger, handler)
		handler = requestIDMiddleware(handler)
		handler = panicMiddleware(logger, handler)

		r.Handle("/admin/", http.StripPrefix("/admin", handler))

	}

	s := &http.Server{
		Addr:              *addr,
		Handler:           maxBodyMiddleware(256*1024, r),
		ReadTimeout:       2 * time.Second,
		ReadHeaderTimeout: 100 * time.Millisecond,
		WriteTimeout:      1 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1024,
	}

	logger.Info("listening", "addr", *addr)
	if err := s.ListenAndServe(); err != nil {
		logger.Error("server error", "err", err)
		return 1
	}

	return 0
}

func checkUsage(db *sql.DB, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		accountID, _ := r.Context().Value("account_id").(string)
		usage, err := usageGet(db, accountID)
		if err != nil {
			logger.ErrorContext(r.Context(), "fetching usage logs", "err", err)
			http.Error(w, `{"error":"fetching usage"}`, http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(usage)
	}
}

func listUsage(db *sql.DB, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		usage, err := usageList(db)
		if err != nil {
			logger.ErrorContext(r.Context(), "fetching usage logs", "err", err)
			http.Error(w, `{"error":"fetching usage"}`, http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(usage)
	}
}

func requestDetails(db *sql.DB, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		requestID := r.PathValue("RequestID")
		details, err := requestGet(db, requestID)
		if err != nil {
			logger.ErrorContext(r.Context(), "fetching details logs", "err", err)
			http.Error(w, `{"error":"fetching details"}`, http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(details)
	}
}

func checkHealth(solver *Solver) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := solver.Ping(); err != nil {
			http.Error(w, `{"status": "unhealthy", "solver": "unreachable"}`, http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	}
}

func ping() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}
}
