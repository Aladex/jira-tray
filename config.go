package main

import (
	"log"
	"os"
	"time"
)

type Config struct {
	JiraURL      string
	JiraToken    string
	JQL          string
	PollInterval time.Duration
}

func LoadConfig() Config {
	jiraURL := os.Getenv("JIRA_URL")
	if jiraURL == "" {
		log.Fatal("JIRA_URL environment variable is required")
	}

	jiraToken := os.Getenv("JIRA_TOKEN")
	if jiraToken == "" {
		log.Fatal("JIRA_TOKEN environment variable is required")
	}

	cfg := Config{
		JiraURL:      jiraURL,
		JiraToken:    jiraToken,
		JQL:          "assignee = currentUser() AND status not in (Done, Closed, Resolved)",
		PollInterval: 5 * time.Minute,
	}

	if v := os.Getenv("JIRA_JQL"); v != "" {
		cfg.JQL = v
	}
	if v := os.Getenv("JIRA_POLL_INTERVAL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.PollInterval = d
		}
	}

	return cfg
}
