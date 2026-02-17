package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gen2brain/beeep"
)

var (
	configMu  sync.RWMutex
	multiCfg  MultiConfig
	instances map[string]*instanceState
)

type instanceState struct {
	mu       sync.RWMutex
	cfg      InstanceConfig
	client   *JiraClient
	issues   []JiraIssue
	lastKeys map[string]bool
	lastErr  error
	lastUpd  time.Time
	cancel   context.CancelFunc
}

type TaskResponse struct {
	Key          string `json:"key"`
	Summary      string `json:"summary"`
	Status       string `json:"status"`
	URL          string `json:"url"`
	InstanceID   string `json:"instanceId"`
	InstanceName string `json:"instanceName"`
}

type StatusResponse struct {
	Count      int               `json:"count"`
	LastUpdate string            `json:"lastUpdate"`
	Error      string            `json:"error,omitempty"`
	Instances  []instanceStatus  `json:"instances,omitempty"`
}

type instanceStatus struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Count      int    `json:"count"`
	LastUpdate string `json:"lastUpdate"`
	Error      string `json:"error,omitempty"`
}

func main() {
	instances = make(map[string]*instanceState)
	multiCfg = LoadConfig()

	for i := range multiCfg.Instances {
		inst := multiCfg.Instances[i]
		if inst.Configured() {
			startInstance(inst)
		}
	}

	if len(multiCfg.Instances) == 0 {
		log.Println("no instances configured, waiting for config")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/tasks", handleTasks)
	mux.HandleFunc("GET /api/status", handleStatus)
	mux.HandleFunc("POST /api/refresh", handleRefresh)
	mux.HandleFunc("GET /api/config", handleGetConfig)
	mux.HandleFunc("POST /api/config", handlePostConfig)
	mux.HandleFunc("GET /api/instances", handleGetInstances)
	mux.HandleFunc("POST /api/instances/sync", handleSyncInstances)

	addr := "127.0.0.1:17842"
	log.Printf("jira-tray listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("http server: %v", err)
	}
}

func startInstance(cfg InstanceConfig) {
	configMu.Lock()
	defer configMu.Unlock()

	// Stop existing if running
	if old, ok := instances[cfg.ID]; ok {
		if old.cancel != nil {
			old.cancel()
		}
	}

	ctx, cancel := context.WithCancel(context.Background())
	is := &instanceState{
		cfg:      cfg,
		client:   NewJiraClient(cfg),
		lastKeys: make(map[string]bool),
		cancel:   cancel,
	}
	instances[cfg.ID] = is

	go func() {
		refreshInstance(is)
		ticker := time.NewTicker(cfg.PollInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				refreshInstance(is)
			}
		}
	}()

	log.Printf("started instance %q (%s)", cfg.Name, cfg.ID)
}

func stopInstance(id string) {
	configMu.Lock()
	defer configMu.Unlock()
	if is, ok := instances[id]; ok {
		if is.cancel != nil {
			is.cancel()
		}
		delete(instances, id)
		log.Printf("stopped instance %q (%s)", is.cfg.Name, id)
	}
}

func restartInstance(cfg InstanceConfig) {
	// stopInstance + startInstance but we handle locking ourselves
	configMu.Lock()
	if old, ok := instances[cfg.ID]; ok {
		if old.cancel != nil {
			old.cancel()
		}
		delete(instances, cfg.ID)
	}
	configMu.Unlock()
	startInstance(cfg)
}

func refreshInstance(is *instanceState) {
	fetched, err := is.client.FetchIssues()

	is.mu.Lock()
	defer is.mu.Unlock()

	is.lastUpd = time.Now()

	if err != nil {
		log.Printf("[%s] jira fetch error: %v", is.cfg.Name, err)
		is.lastErr = err
		return
	}
	is.lastErr = nil
	is.issues = fetched

	currentKeys := make(map[string]bool, len(fetched))
	var newIssues []JiraIssue
	for _, iss := range fetched {
		currentKeys[iss.Key] = true
		if !is.lastKeys[iss.Key] && len(is.lastKeys) > 0 {
			newIssues = append(newIssues, iss)
		}
	}
	is.lastKeys = currentKeys

	for _, iss := range newIssues {
		_ = beeep.Notify(
			fmt.Sprintf("[%s] New: %s", is.cfg.Name, iss.Key),
			iss.Fields.Summary,
			"",
		)
	}
}

// --- API handlers ---

func handleTasks(w http.ResponseWriter, r *http.Request) {
	configMu.RLock()
	defer configMu.RUnlock()

	var tasks []TaskResponse
	for _, is := range instances {
		is.mu.RLock()
		for _, iss := range is.issues {
			tasks = append(tasks, TaskResponse{
				Key:          iss.Key,
				Summary:      iss.Fields.Summary,
				Status:       iss.Fields.Status.Name,
				URL:          is.client.IssueURL(iss.Key),
				InstanceID:   is.cfg.ID,
				InstanceName: is.cfg.Name,
			})
		}
		is.mu.RUnlock()
	}

	if tasks == nil {
		tasks = []TaskResponse{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tasks)
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	configMu.RLock()
	defer configMu.RUnlock()

	resp := StatusResponse{}
	var latestUpd time.Time
	var anyErr string

	for _, is := range instances {
		is.mu.RLock()
		iStatus := instanceStatus{
			ID:    is.cfg.ID,
			Name:  is.cfg.Name,
			Count: len(is.issues),
		}
		if !is.lastUpd.IsZero() {
			iStatus.LastUpdate = is.lastUpd.Format("15:04:05")
			if is.lastUpd.After(latestUpd) {
				latestUpd = is.lastUpd
			}
		}
		if is.lastErr != nil {
			iStatus.Error = is.lastErr.Error()
			anyErr = is.lastErr.Error()
		}
		resp.Count += len(is.issues)
		resp.Instances = append(resp.Instances, iStatus)
		is.mu.RUnlock()
	}

	if !latestUpd.IsZero() {
		resp.LastUpdate = latestUpd.Format("15:04:05")
	}
	if anyErr != "" {
		resp.Error = anyErr
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleRefresh(w http.ResponseWriter, r *http.Request) {
	configMu.RLock()
	var wg sync.WaitGroup
	for _, is := range instances {
		wg.Add(1)
		go func(s *instanceState) {
			defer wg.Done()
			refreshInstance(s)
		}(is)
	}
	configMu.RUnlock()
	wg.Wait()

	handleStatus(w, r)
}

type configResponse struct {
	JiraURL      string `json:"jiraUrl"`
	JQL          string `json:"jql"`
	PollInterval string `json:"pollInterval"`
	Configured   bool   `json:"configured"`
}

func handleGetConfig(w http.ResponseWriter, r *http.Request) {
	configMu.RLock()
	defer configMu.RUnlock()

	// Backward compat: return first instance info
	resp := configResponse{}
	if len(multiCfg.Instances) > 0 {
		inst := multiCfg.Instances[0]
		resp.JiraURL = inst.JiraURL
		resp.JQL = inst.JQL
		resp.PollInterval = inst.PollIntervalStr
		resp.Configured = inst.Configured()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

type configRequest struct {
	JiraURL      string `json:"jiraUrl"`
	JiraToken    string `json:"jiraToken"`
	JQL          string `json:"jql"`
	PollInterval string `json:"pollInterval"`
}

func handlePostConfig(w http.ResponseWriter, r *http.Request) {
	var req configRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	configMu.Lock()

	// Backward compat: update or create "legacy" instance
	inst := multiCfg.FindByID("legacy")
	if inst == nil {
		// Check if there's a single instance we can update
		if len(multiCfg.Instances) == 1 && multiCfg.Instances[0].ID != "env-override" {
			inst = &multiCfg.Instances[0]
		}
	}

	if inst == nil {
		newInst := InstanceConfig{
			ID:   "legacy",
			Name: "Jira",
		}
		multiCfg.Add(newInst)
		inst = multiCfg.FindByID("legacy")
	}

	changed := false
	if req.JiraURL != "" && req.JiraURL != inst.JiraURL {
		inst.JiraURL = req.JiraURL
		changed = true
	}
	if req.JiraToken != "" && req.JiraToken != inst.JiraToken {
		inst.JiraToken = req.JiraToken
		changed = true
	}
	if req.JQL != "" && req.JQL != inst.JQL {
		inst.JQL = req.JQL
		changed = true
	}
	if req.PollInterval != "" {
		if d, err := time.ParseDuration(req.PollInterval); err == nil && d != inst.PollInterval {
			inst.PollInterval = d
			inst.PollIntervalStr = req.PollInterval
			changed = true
		}
	}

	if changed {
		_ = multiCfg.save()
	}
	configured := inst.Configured()
	instCopy := *inst
	configMu.Unlock()

	if changed && configured {
		restartInstance(instCopy)
		log.Println("legacy config updated, polling restarted")
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

type instanceResponse struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	JiraURL      string `json:"jiraUrl"`
	JiraEmail    string `json:"jiraEmail,omitempty"`
	JQL          string `json:"jql"`
	PollInterval string `json:"pollInterval"`
}

func handleGetInstances(w http.ResponseWriter, r *http.Request) {
	configMu.RLock()
	defer configMu.RUnlock()

	resp := make([]instanceResponse, len(multiCfg.Instances))
	for i, inst := range multiCfg.Instances {
		resp[i] = instanceResponse{
			ID:           inst.ID,
			Name:         inst.Name,
			JiraURL:      inst.JiraURL,
			JiraEmail:    inst.JiraEmail,
			JQL:          inst.JQL,
			PollInterval: inst.PollIntervalStr,
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleSyncInstances(w http.ResponseWriter, r *http.Request) {
	var incoming []InstanceConfig
	if err := json.NewDecoder(r.Body).Decode(&incoming); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	configMu.Lock()

	// Build set of incoming IDs
	incomingIDs := make(map[string]bool, len(incoming))
	for i := range incoming {
		if incoming[i].ID == "" {
			incoming[i].ID = generateID()
		}
		incoming[i].applyDefaults()
		incomingIDs[incoming[i].ID] = true
	}

	// Find instances to stop (present in current, absent in incoming, not env-override)
	var toStop []string
	for _, inst := range multiCfg.Instances {
		if inst.ID == "env-override" {
			continue
		}
		if !incomingIDs[inst.ID] {
			toStop = append(toStop, inst.ID)
		}
	}
	configMu.Unlock()

	// Stop removed instances
	for _, id := range toStop {
		stopInstance(id)
	}

	configMu.Lock()
	// Preserve env-override if it exists
	var envInst *InstanceConfig
	for _, inst := range multiCfg.Instances {
		if inst.ID == "env-override" {
			instCopy := inst
			envInst = &instCopy
			break
		}
	}

	multiCfg.Instances = incoming
	if envInst != nil {
		// Re-add env-override if not in incoming
		if !incomingIDs["env-override"] {
			multiCfg.Instances = append(multiCfg.Instances, *envInst)
		}
	}

	_ = multiCfg.save()
	configMu.Unlock()

	// Start/restart all incoming instances
	for _, inst := range incoming {
		if inst.Configured() {
			restartInstance(inst)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}
