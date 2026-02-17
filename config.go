package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type InstanceConfig struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	JiraURL         string `json:"jiraUrl"`
	JiraToken       string `json:"jiraToken"`
	JiraEmail       string `json:"jiraEmail,omitempty"`
	JQL             string `json:"jql"`
	PollIntervalStr string `json:"pollInterval"`
	PollInterval    time.Duration `json:"-"`
}

type MultiConfig struct {
	Instances []InstanceConfig `json:"instances"`
}

// oldFlatConfig is the legacy single-instance format for migration.
type oldFlatConfig struct {
	JiraURL         string `json:"jiraUrl"`
	JiraToken       string `json:"jiraToken"`
	JQL             string `json:"jql"`
	PollIntervalStr string `json:"pollInterval"`
}

func generateID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%x", b)
}

func configFilePath() string {
	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(dir, "jira-tray", "config.json")
}

func (ic *InstanceConfig) parseDuration() {
	if ic.PollIntervalStr != "" {
		if d, err := time.ParseDuration(ic.PollIntervalStr); err == nil {
			ic.PollInterval = d
		}
	}
	if ic.PollInterval <= 0 {
		ic.PollInterval = 5 * time.Minute
		ic.PollIntervalStr = "5m"
	}
}

func (ic *InstanceConfig) applyDefaults() {
	if ic.JQL == "" {
		ic.JQL = "assignee = currentUser() AND status not in (Done, Closed, Resolved)"
	}
	ic.parseDuration()
}

func (ic InstanceConfig) Configured() bool {
	return ic.JiraURL != "" && ic.JiraToken != ""
}

func LoadConfig() MultiConfig {
	mc := MultiConfig{}

	data, err := os.ReadFile(configFilePath())
	if err == nil {
		mc = migrateOrParse(data)
	}

	// Env var override: create synthetic instance
	envURL := os.Getenv("JIRA_URL")
	envToken := os.Getenv("JIRA_TOKEN")
	if envURL != "" && envToken != "" {
		envInst := InstanceConfig{
			ID:      "env-override",
			Name:    "Environment",
			JiraURL: envURL,
			JiraToken: envToken,
			JQL:     "assignee = currentUser() AND status not in (Done, Closed, Resolved)",
		}
		if v := os.Getenv("JIRA_EMAIL"); v != "" {
			envInst.JiraEmail = v
		}
		if v := os.Getenv("JIRA_JQL"); v != "" {
			envInst.JQL = v
		}
		if v := os.Getenv("JIRA_POLL_INTERVAL"); v != "" {
			envInst.PollIntervalStr = v
		}
		envInst.applyDefaults()

		// Replace existing env-override or append
		found := false
		for i, inst := range mc.Instances {
			if inst.ID == "env-override" {
				mc.Instances[i] = envInst
				found = true
				break
			}
		}
		if !found {
			mc.Instances = append(mc.Instances, envInst)
		}
	}

	return mc
}

func migrateOrParse(data []byte) MultiConfig {
	// Try new format first
	var mc MultiConfig
	if err := json.Unmarshal(data, &mc); err == nil && len(mc.Instances) > 0 {
		for i := range mc.Instances {
			mc.Instances[i].applyDefaults()
		}
		return mc
	}

	// Try old flat format
	var old oldFlatConfig
	if err := json.Unmarshal(data, &old); err == nil && old.JiraURL != "" {
		inst := InstanceConfig{
			ID:              "legacy",
			Name:            "Jira",
			JiraURL:         old.JiraURL,
			JiraToken:       old.JiraToken,
			JQL:             old.JQL,
			PollIntervalStr: old.PollIntervalStr,
		}
		inst.applyDefaults()
		mc.Instances = []InstanceConfig{inst}
		// Persist migrated format
		_ = mc.save()
		return mc
	}

	return MultiConfig{}
}

func (mc MultiConfig) save() error {
	path := configFilePath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(mc, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func (mc *MultiConfig) FindByID(id string) *InstanceConfig {
	for i := range mc.Instances {
		if mc.Instances[i].ID == id {
			return &mc.Instances[i]
		}
	}
	return nil
}

func (mc *MultiConfig) Add(inst InstanceConfig) {
	if inst.ID == "" {
		inst.ID = generateID()
	}
	inst.applyDefaults()
	mc.Instances = append(mc.Instances, inst)
}

func (mc *MultiConfig) Update(inst InstanceConfig) bool {
	for i := range mc.Instances {
		if mc.Instances[i].ID == inst.ID {
			inst.applyDefaults()
			mc.Instances[i] = inst
			return true
		}
	}
	return false
}

func (mc *MultiConfig) Remove(id string) bool {
	for i := range mc.Instances {
		if mc.Instances[i].ID == id {
			mc.Instances = append(mc.Instances[:i], mc.Instances[i+1:]...)
			return true
		}
	}
	return false
}
