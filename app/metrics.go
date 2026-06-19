package main

import (
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// metrics is a zero-dependency Prometheus text-format exposition layer.
// Covers just what the alerts and dashboard need: a request counter and a latency histogram.
type metrics struct {
	mu        sync.Mutex
	requests  map[string]float64   // http_requests_total{method,path,status}
	hist      map[string]*histogram // http_request_duration_seconds, keyed by method+path
	buildInfo *labeledGauge        // app_build_info{version}
}

var latencyBuckets = []float64{
	0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10,
}

type histogram struct {
	bucket []uint64 // raw per-bucket
	sum    float64
	count  uint64
}

func newHistogram() *histogram {
	return &histogram{bucket: make([]uint64, len(latencyBuckets))}
}

func (h *histogram) observe(v float64) {
	h.sum += v
	h.count++
	for i, b := range latencyBuckets {
		if v <= b {
			h.bucket[i]++
		}
	}
}

type labeledGauge struct {
	mu     sync.Mutex
	name   string
	values map[string]float64
}

func (g *labeledGauge) set(labels map[string]string, v float64) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.values[encodeLabels(labels)] = v
}

func newMetrics() *metrics {
	return &metrics{
		requests:  map[string]float64{},
		hist:      map[string]*histogram{},
		buildInfo: &labeledGauge{name: "app_build_info", values: map[string]float64{}},
	}
}

// instrument wraps a handler and records status + latency under a fixed route label
// to avoid unbounded cardinality from raw request paths.
func (m *metrics) instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r)
		elapsed := time.Since(start).Seconds()

		m.mu.Lock()
		ckey := encodeLabels(map[string]string{
			"method": r.Method,
			"path":   route,
			"status": strconv.Itoa(rec.status),
		})
		m.requests[ckey]++
		hkey := r.Method + "|" + route
		h, ok := m.hist[hkey]
		if !ok {
			h = newHistogram()
			m.hist[hkey] = h
		}
		h.observe(elapsed)
		m.mu.Unlock()
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// ServeHTTP renders the Prometheus text exposition format.
func (m *metrics) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	m.mu.Lock()
	defer m.mu.Unlock()
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	var b strings.Builder

	b.WriteString("# HELP app_build_info Build metadata.\n")
	b.WriteString("# TYPE app_build_info gauge\n")
	m.buildInfo.mu.Lock()
	for lbls, v := range m.buildInfo.values {
		fmt.Fprintf(&b, "app_build_info%s %g\n", lbls, v)
	}
	m.buildInfo.mu.Unlock()

	b.WriteString("# HELP http_requests_total Total HTTP requests.\n")
	b.WriteString("# TYPE http_requests_total counter\n")
	for _, k := range sortedKeys(m.requests) {
		fmt.Fprintf(&b, "http_requests_total%s %g\n", k, m.requests[k])
	}

	b.WriteString("# HELP http_request_duration_seconds Request latency.\n")
	b.WriteString("# TYPE http_request_duration_seconds histogram\n")
	for _, hkey := range sortedHistKeys(m.hist) {
		parts := strings.SplitN(hkey, "|", 2)
		method, path := parts[0], parts[1]
		h := m.hist[hkey]
		base := map[string]string{"method": method, "path": path}
		// observe() increments every bucket whose bound >= v, so h.bucket[i] is already cumulative.
		for i, bound := range latencyBuckets {
			lbls := withLabel(base, "le", formatBound(bound))
			fmt.Fprintf(&b, "http_request_duration_seconds_bucket%s %d\n", encodeLabels(lbls), h.bucket[i])
		}
		infLbls := withLabel(base, "le", "+Inf")
		fmt.Fprintf(&b, "http_request_duration_seconds_bucket%s %d\n", encodeLabels(infLbls), h.count)
		fmt.Fprintf(&b, "http_request_duration_seconds_sum%s %g\n", encodeLabels(base), h.sum)
		fmt.Fprintf(&b, "http_request_duration_seconds_count%s %d\n", encodeLabels(base), h.count)
	}

	_, _ = w.Write([]byte(b.String()))
}

func formatBound(b float64) string {
	return strconv.FormatFloat(b, 'g', -1, 64)
}

func withLabel(base map[string]string, k, v string) map[string]string {
	out := make(map[string]string, len(base)+1)
	for kk, vv := range base {
		out[kk] = vv
	}
	out[k] = v
	return out
}

func encodeLabels(labels map[string]string) string {
	if len(labels) == 0 {
		return ""
	}
	keys := make([]string, 0, len(labels))
	for k := range labels {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var parts []string
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s=%q", k, labels[k]))
	}
	return "{" + strings.Join(parts, ",") + "}"
}

func sortedKeys(m map[string]float64) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedHistKeys(m map[string]*histogram) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
