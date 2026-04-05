package main

import (
	"context"
	"crypto/rand"
	"net/http"
)

func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("CF-Ray")
		if id == "" {
			id = rand.Text()
		}
		ctx := context.WithValue(r.Context(), "request_id", id)
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
