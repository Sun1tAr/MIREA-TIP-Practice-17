package authclient

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared/middleware"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
}

func NewClient(baseURL string, timeout time.Duration) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

func (c *Client) VerifyToken(ctx context.Context, token string) (bool, string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/v1/auth/verify", nil)
	if err != nil {
		return false, "", fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	if requestID := middleware.GetRequestID(ctx); requestID != "" {
		req.Header.Set("X-Request-ID", requestID)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, "", fmt.Errorf("auth request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, "", nil
	}

	var verifyResp struct {
		Valid   bool   `json:"valid"`
		Subject string `json:"subject"`
		Error   string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&verifyResp); err != nil {
		return false, "", fmt.Errorf("failed to decode auth response: %w", err)
	}

	if verifyResp.Valid {
		return true, verifyResp.Subject, nil
	}
	return false, "", nil
}
