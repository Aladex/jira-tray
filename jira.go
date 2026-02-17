package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
)

type JiraIssue struct {
	Key    string `json:"key"`
	Fields struct {
		Summary string `json:"summary"`
		Status  struct {
			Name string `json:"name"`
		} `json:"status"`
	} `json:"fields"`
}

type jiraSearchResult struct {
	Issues []JiraIssue `json:"issues"`
	Total  int         `json:"total"`
}

type JiraClient struct {
	cfg Config
	hc  *http.Client
}

func NewJiraClient(cfg Config) *JiraClient {
	return &JiraClient{cfg: cfg, hc: &http.Client{}}
}

func (c *JiraClient) FetchIssues() ([]JiraIssue, error) {
	u := fmt.Sprintf("%s/rest/api/2/search?jql=%s&fields=summary,status&maxResults=50",
		c.cfg.JiraURL, url.QueryEscape(c.cfg.JQL))

	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.cfg.JiraToken)
	req.Header.Set("Accept", "application/json")

	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("jira API %d: %s", resp.StatusCode, string(body))
	}

	var result jiraSearchResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result.Issues, nil
}

func (c *JiraClient) IssueURL(key string) string {
	return fmt.Sprintf("%s/browse/%s", c.cfg.JiraURL, key)
}
