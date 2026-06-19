// orders-api is a minimal stand-in service for the platform foundation.
// Zero external dependencies — stdlib only. Ships in a distroless image.
//
// GET /            request metrics
// GET /healthz     liveness
// GET /readyz      readiness (fails during shutdown drain)
// GET /metrics     Prometheus text format
// GET /debug/fail  fault injection, only when DEBUG_ENDPOINTS=true
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var (
	version = "dev" // overridden at build time via -ldflags

	injectFailRate atomic.Uint64 // rate*1e6, set via /debug/fail?rate=
	injectLatency  atomic.Int64  // extra ms, set via /debug/fail?latency_ms=
	ready          atomic.Bool   // flips after warmup; readiness probe reflects it
)

func main() {
	port := getenv("PORT", "8080")
	warmup := mustDuration(getenv("WARMUP", "3s"))
	debugEndpoints := getenv("DEBUG_ENDPOINTS", "false") == "true"

	m := newMetrics()
	m.buildInfo.set(map[string]string{"version": version}, 1)

	mux := http.NewServeMux()
	mux.Handle("/", m.instrument("/", http.HandlerFunc(rootHandler)))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			http.Error(w, "warming up", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "ready")
	})
	mux.Handle("/metrics", m)
	if debugEndpoints {
		mux.HandleFunc("/debug/fail", debugFailHandler)
		log.Println("debug endpoints ENABLED (/debug/fail)")
	}

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		time.Sleep(warmup)
		ready.Store(true)
		log.Printf("ready after %s warmup", warmup)
	}()

	go func() {
		log.Printf("orders-api %s listening on :%s", version, port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server error: %v", err)
		}
	}()

	// Graceful shutdown: stop accepting new work, drain in-flight requests.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("shutdown signal received, draining...")
	ready.Store(false) // fail readiness so we are pulled from endpoints first
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	}
	log.Println("bye")
}

func rootHandler(w http.ResponseWriter, _ *http.Request) {
	if d := injectLatency.Load(); d > 0 {
		time.Sleep(time.Duration(d) * time.Millisecond)
	}
	if rate := float64(injectFailRate.Load()) / 1e6; rate > 0 {
		if pseudoRand() < rate {
			http.Error(w, "injected failure", http.StatusInternalServerError)
			return
		}
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "orders-api: ok")
}

// debugFailHandler tunes fault injection: /debug/fail?rate=0.5&latency_ms=300
func debugFailHandler(w http.ResponseWriter, r *http.Request) {
	if v := r.URL.Query().Get("rate"); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil || f < 0 || f > 1 {
			http.Error(w, "rate must be in [0,1]", http.StatusBadRequest)
			return
		}
		injectFailRate.Store(uint64(f * 1e6))
	}
	if v := r.URL.Query().Get("latency_ms"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err != nil || n < 0 {
			http.Error(w, "latency_ms must be >= 0", http.StatusBadRequest)
			return
		}
		injectLatency.Store(n)
	}
	fmt.Fprintf(w, "fail_rate=%.3f latency_ms=%d\n",
		float64(injectFailRate.Load())/1e6, injectLatency.Load())
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func mustDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		log.Fatalf("invalid duration %q: %v", s, err)
	}
	return d
}

// pseudoRand is xorshift64 — no math/rand import, keeps the binary small.
var randState atomic.Uint64

func pseudoRand() float64 {
	for {
		old := randState.Load()
		x := old
		if x == 0 {
			x = uint64(time.Now().UnixNano())
		}
		x ^= x << 13
		x ^= x >> 7
		x ^= x << 17
		if randState.CompareAndSwap(old, x) {
			return float64(x>>11) / float64(1<<53)
		}
	}
}

