package main

import (
	"net/http"
	"slices"
)

func allowedAccounts(accounts []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		accountID, _ := r.Context().Value("account_id").(string)
		if !slices.Contains(accounts, accountID) {
			http.Error(w, `{"error": "forbidden"}`, http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	})
}
