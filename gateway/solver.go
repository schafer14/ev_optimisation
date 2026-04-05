package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"
)

type Solver struct {
	proxy *httputil.ReverseProxy
	url   string
}

func NewSolver(rawURL string) *Solver {
	u, _ := url.Parse(rawURL)
	return &Solver{
		proxy: httputil.NewSingleHostReverseProxy(u),
		url:   rawURL,
	}
}

func (s *Solver) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.proxy.ServeHTTP(w, r)
}

func (s *Solver) Ping() error {
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()

	reqBody := `{"evs":[], "bess": []}`

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.url+"/v1-alpha/plan", strings.NewReader(reqBody))
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("solver unhealthy: %d", resp.StatusCode)
	}
	return nil
}
