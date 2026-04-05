package main

import (
	"context"
	"log/slog"
	"os"
)

type contextHandler struct {
	slog.Handler
}

func (h *contextHandler) Handle(ctx context.Context, r slog.Record) error {
	if id, ok := ctx.Value("request_id").(string); ok {
		r.AddAttrs(slog.String("request_id", id))
	}
	if id, ok := ctx.Value("account_id").(string); ok {
		r.AddAttrs(slog.String("account_id", id))
	}
	return h.Handler.Handle(ctx, r)
}

type LogFormat int

const (
	LogFormatPretty LogFormat = iota
	LogFormatJSON
)

func newLogger(format LogFormat, level slog.Level) *slog.Logger {
	opts := &slog.HandlerOptions{Level: level}
	var handler slog.Handler
	switch format {
	case LogFormatPretty:
		handler = slog.NewTextHandler(os.Stdout, opts)
	case LogFormatJSON:
		handler = slog.NewJSONHandler(os.Stdout, opts)
	}
	return slog.New(&contextHandler{Handler: handler})
}
