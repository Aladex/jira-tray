package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

type Config struct {
	JiraURL         string `json:"jiraUrl"`
	JiraToken       string `json:"jiraToken"`
	JQL             string `json:"jql"`
	PollIntervalStr string `json:"pollInterval"`
	PollInterval    time.Duration
}

func configFilePath() string {
	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(dir, "jira-tray", "config.json")
}

func loadConfigFile() (Config, error) {
	var cfg Config
	data, err := os.ReadFile(configFilePath())
	if err != nil {
		return cfg, err
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, err
	}
	cfg.parseDuration()
	return cfg, nil
}

func (c *Config) parseDuration() {
	if c.PollIntervalStr != "" {
		if d, err := time.ParseDuration(c.PollIntervalStr); err == nil {
			c.PollInterval = d
		}
	}
}

func (c Config) save() error {
	path := configFilePath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	if c.PollInterval > 0 {
		c.PollIntervalStr = c.PollInterval.String()
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

func LoadConfig() Config {
	cfg := Config{
		JQL:             "assignee = currentUser() AND status not in (Done, Closed, Resolved)",
		PollInterval:    5 * time.Minute,
		PollIntervalStr: "5m",
	}

	if fileCfg, err := loadConfigFile(); err == nil {
		if fileCfg.JiraURL != "" {
			cfg.JiraURL = fileCfg.JiraURL
		}
		if fileCfg.JiraToken != "" {
			cfg.JiraToken = fileCfg.JiraToken
		}
		if fileCfg.JQL != "" {
			cfg.JQL = fileCfg.JQL
		}
		if fileCfg.PollInterval > 0 {
			cfg.PollInterval = fileCfg.PollInterval
			cfg.PollIntervalStr = fileCfg.PollIntervalStr
		}
	}

	if v := os.Getenv("JIRA_URL"); v != "" {
		cfg.JiraURL = v
	}
	if v := os.Getenv("JIRA_TOKEN"); v != "" {
		cfg.JiraToken = v
	}
	if v := os.Getenv("JIRA_JQL"); v != "" {
		cfg.JQL = v
	}
	if v := os.Getenv("JIRA_POLL_INTERVAL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.PollInterval = d
			cfg.PollIntervalStr = v
		}
	}

	return cfg
}

func (c Config) Configured() bool {
	return c.JiraURL != "" && c.JiraToken != ""
}
