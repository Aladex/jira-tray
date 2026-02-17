package main

import (
	"encoding/base64"
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
	cfg InstanceConfig
	hc  *http.Client
}

func NewJiraClient(cfg InstanceConfig) *JiraClient {
	return &JiraClient{cfg: cfg, hc: &http.Client{}}
}

func (c *JiraClient) isCloud() bool {
	return c.cfg.JiraEmail != ""
}

func (c *JiraClient) FetchIssues() ([]JiraIssue, error) {
	var u string
	if c.isCloud() {
		// Jira Cloud: API v2/search removed (410), use v3
		u = fmt.Sprintf("%s/rest/api/3/search/jql?jql=%s&fields=summary,status&maxResults=50",
			c.cfg.JiraURL, url.QueryEscape(c.cfg.JQL))
	} else {
		u = fmt.Sprintf("%s/rest/api/2/search?jql=%s&fields=summary,status&maxResults=50",
			c.cfg.JiraURL, url.QueryEscape(c.cfg.JQL))
	}

	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", c.authHeader())
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

func (c *JiraClient) authHeader() string {
	if c.cfg.JiraEmail != "" {
		creds := c.cfg.JiraEmail + ":" + c.cfg.JiraToken
		return "Basic " + base64.StdEncoding.EncodeToString([]byte(creds))
	}
	return "Bearer " + c.cfg.JiraToken
}

func (c *JiraClient) IssueURL(key string) string {
	return fmt.Sprintf("%s/browse/%s", c.cfg.JiraURL, key)
}
