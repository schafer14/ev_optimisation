package main

import (
	"log/slog"
	"net/http"
)

func panicMiddleware(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				logger.ErrorContext(r.Context(), "panic",
					"err", err,
					"method", r.Method,
					"path", r.URL.Path,
				)
				http.Error(w, `{"error": "internal server error"}`, http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
