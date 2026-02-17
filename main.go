package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gen2brain/beeep"
)

var (
	cfg      Config
	client   *JiraClient
	mu       sync.RWMutex
	issues   []JiraIssue
	lastKeys map[string]bool
	lastErr  error
	lastUpd  time.Time
)

type TaskResponse struct {
	Key     string `json:"key"`
	Summary string `json:"summary"`
	Status  string `json:"status"`
	URL     string `json:"url"`
}

type StatusResponse struct {
	Count      int    `json:"count"`
	LastUpdate string `json:"lastUpdate"`
	Error      string `json:"error,omitempty"`
}

func main() {
	cfg = LoadConfig()
	client = NewJiraClient(cfg)
	lastKeys = make(map[string]bool)

	// Initial fetch + polling
	go func() {
		refresh()
		ticker := time.NewTicker(cfg.PollInterval)
		defer ticker.Stop()
		for range ticker.C {
			refresh()
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/tasks", handleTasks)
	mux.HandleFunc("GET /api/status", handleStatus)
	mux.HandleFunc("POST /api/refresh", handleRefresh)

	addr := "127.0.0.1:17842"
	log.Printf("jira-tray listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("http server: %v", err)
	}
}

func handleTasks(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	defer mu.RUnlock()

	tasks := make([]TaskResponse, len(issues))
	for i, iss := range issues {
		tasks[i] = TaskResponse{
			Key:     iss.Key,
			Summary: iss.Fields.Summary,
			Status:  iss.Fields.Status.Name,
			URL:     client.IssueURL(iss.Key),
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tasks)
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	defer mu.RUnlock()

	resp := StatusResponse{
		Count: len(issues),
	}
	if !lastUpd.IsZero() {
		resp.LastUpdate = lastUpd.Format("15:04:05")
	}
	if lastErr != nil {
		resp.Error = lastErr.Error()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleRefresh(w http.ResponseWriter, r *http.Request) {
	refresh()

	mu.RLock()
	defer mu.RUnlock()

	resp := StatusResponse{
		Count: len(issues),
	}
	if !lastUpd.IsZero() {
		resp.LastUpdate = lastUpd.Format("15:04:05")
	}
	if lastErr != nil {
		resp.Error = lastErr.Error()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func refresh() {
	fetched, err := client.FetchIssues()

	mu.Lock()
	defer mu.Unlock()

	lastUpd = time.Now()

	if err != nil {
		log.Printf("jira fetch error: %v", err)
		lastErr = err
		return
	}
	lastErr = nil
	issues = fetched

	// Detect new issues for notifications
	currentKeys := make(map[string]bool, len(fetched))
	var newIssues []JiraIssue
	for _, iss := range fetched {
		currentKeys[iss.Key] = true
		if !lastKeys[iss.Key] && len(lastKeys) > 0 {
			newIssues = append(newIssues, iss)
		}
	}
	lastKeys = currentKeys

	for _, iss := range newIssues {
		_ = beeep.Notify(
			fmt.Sprintf("New Jira: %s", iss.Key),
			iss.Fields.Summary,
			"",
		)
	}
}
