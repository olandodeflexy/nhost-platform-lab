package server

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestServer() *Server {
	return New(Info{
		Version:     "1.2.3",
		Commit:      "abc123",
		BuildTime:   "reproducible",
		Region:      "eu-west-1",
		Environment: "test",
	}, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func TestRootIncludesBuildAndRuntimeMetadata(t *testing.T) {
	s := newTestServer()
	recorder := httptest.NewRecorder()
	s.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}

	var body map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["version"] != "1.2.3" || body["region"] != "eu-west-1" {
		t.Fatalf("unexpected response: %#v", body)
	}
}

func TestHealthAndReadinessAreIndependent(t *testing.T) {
	s := newTestServer()

	health := httptest.NewRecorder()
	s.Handler().ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if health.Code != http.StatusOK {
		t.Fatalf("health status = %d, want 200", health.Code)
	}

	notReady := httptest.NewRecorder()
	s.Handler().ServeHTTP(notReady, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if notReady.Code != http.StatusServiceUnavailable {
		t.Fatalf("initial readiness status = %d, want 503", notReady.Code)
	}

	s.SetReady(true)
	ready := httptest.NewRecorder()
	s.Handler().ServeHTTP(ready, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if ready.Code != http.StatusOK {
		t.Fatalf("ready status = %d, want 200", ready.Code)
	}
}

func TestMetricsExposeRequestCountAndReadiness(t *testing.T) {
	s := newTestServer()
	s.SetReady(true)

	recorder := httptest.NewRecorder()
	s.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	if !strings.Contains(recorder.Body.String(), "demo_api_http_requests_total 1") {
		t.Fatalf("request metric missing: %s", recorder.Body.String())
	}
	if !strings.Contains(recorder.Body.String(), "demo_api_ready 1") {
		t.Fatalf("readiness metric missing: %s", recorder.Body.String())
	}
}

func TestUnsupportedMethodReturnsMethodNotAllowed(t *testing.T) {
	s := newTestServer()
	recorder := httptest.NewRecorder()
	s.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodPost, "/healthz", nil))

	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", recorder.Code)
	}
}
