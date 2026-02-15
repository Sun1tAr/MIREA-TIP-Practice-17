# create_project.ps1
# Запустите этот скрипт в PowerShell. Он создаст папку tech-ip-sem2 и все необходимые файлы.

$root = Join-Path (Get-Location) "tech-ip-sem2"
if (!(Test-Path $root)) {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
}

function Write-File($relativePath, $content) {
    $fullPath = Join-Path $root $relativePath
    $dir = Split-Path $fullPath -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # UTF8 без BOM
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($fullPath, $content, $utf8)
    Write-Host "Created: tech-ip-sem2/$relativePath"
}

# ==============================
# 1. Shared module
# ==============================

Write-File "shared/go.mod" @"
module github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared

go 1.22

require github.com/google/uuid v1.6.0
"@

Write-File "shared/middleware/requestid.go" @"
package middleware

import (
    "context"
    "net/http"

    "github.com/google/uuid"
)

type contextKey string

const RequestIDKey contextKey = "requestID"

func RequestIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        requestID := r.Header.Get("X-Request-ID")
        if requestID == "" {
            requestID = uuid.New().String()
        }
        ctx := context.WithValue(r.Context(), RequestIDKey, requestID)
        w.Header().Set("X-Request-ID", requestID)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

func GetRequestID(ctx context.Context) string {
    if val, ok := ctx.Value(RequestIDKey).(string); ok {
        return val
    }
    return ""
}
"@

Write-File "shared/middleware/logging.go" @"
package middleware

import (
    "log"
    "net/http"
    "time"
)

type responseWriter struct {
    http.ResponseWriter
    statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
    rw.statusCode = code
    rw.ResponseWriter.WriteHeader(code)
}

func LoggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
        next.ServeHTTP(wrapped, r)
        requestID := GetRequestID(r.Context())
        log.Printf("[%s] %s %s %d %v", requestID, r.Method, r.URL.Path, wrapped.statusCode, time.Since(start))
    })
}
"@

Write-File "shared/httpx/client.go" @"
package httpx

// Здесь можно разместить общие функции для HTTP-клиентов.
"@

# ==============================
# 2. Auth service
# ==============================

Write-File "services/auth/go.mod" @"
module github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/auth

go 1.22

require (
    github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared v0.0.0
    github.com/google/uuid v1.6.0
)

replace github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared => ../../shared
"@

Write-File "services/auth/cmd/auth/main.go" @"
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"

    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/auth/internal/http"
    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared/middleware"
)

func main() {
    port := os.Getenv("AUTH_PORT")
    if port == "" {
        port = "8081"
    }

    mux := http.NewServeMux()
    mux.HandleFunc("POST /v1/auth/login", http.LoginHandler)
    mux.HandleFunc("GET /v1/auth/verify", http.VerifyHandler)

    handler := middleware.RequestIDMiddleware(middleware.LoggingMiddleware(mux))

    addr := fmt.Sprintf(":%s", port)
    log.Printf("Auth service starting on %s", addr)
    if err := http.ListenAndServe(addr, handler); err != nil {
        log.Fatal(err)
    }
}
"@

Write-File "services/auth/internal/http/handlers.go" @"
package http

import (
    "encoding/json"
    "fmt"
    "net/http"

    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/auth/internal/service"
)

type loginRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
}

type loginResponse struct {
    AccessToken string `json:"access_token"`
    TokenType   string `json:"token_type"`
}

func LoginHandler(w http.ResponseWriter, r *http.Request) {
    var req loginRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "Invalid request body", http.StatusBadRequest)
        return
    }

    token, err := service.Login(req.Username, req.Password)
    if err != nil {
        http.Error(w, err.Error(), http.StatusUnauthorized)
        return
    }

    resp := loginResponse{
        AccessToken: token,
        TokenType:   "Bearer",
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(resp)
}

type verifyResponse struct {
    Valid   bool   `json:"valid"`
    Subject string `json:"subject,omitempty"`
    Error   string `json:"error,omitempty"`
}

func VerifyHandler(w http.ResponseWriter, r *http.Request) {
    authHeader := r.Header.Get("Authorization")
    if authHeader == "" {
        w.WriteHeader(http.StatusUnauthorized)
        json.NewEncoder(w).Encode(verifyResponse{Valid: false, Error: "missing authorization header"})
        return
    }

    var token string
    _, err := fmt.Sscanf(authHeader, "Bearer %s", &token)
    if err != nil {
        w.WriteHeader(http.StatusUnauthorized)
        json.NewEncoder(w).Encode(verifyResponse{Valid: false, Error: "invalid authorization header format"})
        return
    }

    valid, subject := service.VerifyToken(token)
    if !valid {
        w.WriteHeader(http.StatusUnauthorized)
        json.NewEncoder(w).Encode(verifyResponse{Valid: false, Error: "invalid token"})
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(verifyResponse{Valid: true, Subject: subject})
}
"@

Write-File "services/auth/internal/service/auth.go" @"
package service

import "errors"

const (
    validUsername = "student"
    validPassword = "student"
    validToken    = "demo-token"
    subject       = "student"
)

func Login(username, password string) (string, error) {
    if username == validUsername && password == validPassword {
        return validToken, nil
    }
    return "", errors.New("invalid credentials")
}

func VerifyToken(token string) (bool, string) {
    if token == validToken {
        return true, subject
    }
    return false, ""
}
"@

# ==============================
# 3. Tasks service
# ==============================

Write-File "services/tasks/go.mod" @"
module github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks

go 1.22

require (
    github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared v0.0.0
    github.com/google/uuid v1.6.0
)

replace github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared => ../../shared
"@

Write-File "services/tasks/cmd/tasks/main.go" @"
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
    "time"

    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/client/authclient"
    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/http"
    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/service"
    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared/middleware"
)

func main() {
    tasksPort := os.Getenv("TASKS_PORT")
    if tasksPort == "" {
        tasksPort = "8082"
    }
    authBaseURL := os.Getenv("AUTH_BASE_URL")
    if authBaseURL == "" {
        authBaseURL = "http://localhost:8081"
    }

    authClient := authclient.NewClient(authBaseURL, 3*time.Second)
    taskService := service.NewTaskService()
    taskHandler := http.NewTaskHandler(taskService, authClient)

    mux := http.NewServeMux()
    mux.HandleFunc("POST /v1/tasks", taskHandler.CreateTask)
    mux.HandleFunc("GET /v1/tasks", taskHandler.ListTasks)
    mux.HandleFunc("GET /v1/tasks/{id}", taskHandler.GetTask)
    mux.HandleFunc("PATCH /v1/tasks/{id}", taskHandler.UpdateTask)
    mux.HandleFunc("DELETE /v1/tasks/{id}", taskHandler.DeleteTask)

    handler := middleware.RequestIDMiddleware(middleware.LoggingMiddleware(mux))

    addr := fmt.Sprintf(":%s", tasksPort)
    log.Printf("Tasks service starting on %s", addr)
    if err := http.ListenAndServe(addr, handler); err != nil {
        log.Fatal(err)
    }
}
"@

Write-File "services/tasks/internal/client/authclient/client.go" @"
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
"@

Write-File "services/tasks/internal/service/tasks.go" @"
package service

import (
    "fmt"
    "sync"
    "time"
)

type Task struct {
    ID          string    `json:"id"`
    Title       string    `json:"title"`
    Description string    `json:"description"`
    DueDate     string    `json:"due_date,omitempty"`
    Done        bool      `json:"done"`
    CreatedAt   time.Time `json:"-"`
    UpdatedAt   time.Time `json:"-"`
}

type TaskService struct {
    mu    sync.RWMutex
    tasks map[string]Task
}

func NewTaskService() *TaskService {
    return &TaskService{
        tasks: make(map[string]Task),
    }
}

func generateID() string {
    return fmt.Sprintf("t_%d", time.Now().UnixNano())
}

func (s *TaskService) Create(task Task) Task {
    s.mu.Lock()
    defer s.mu.Unlock()
    task.ID = generateID()
    task.CreatedAt = time.Now()
    task.UpdatedAt = time.Now()
    s.tasks[task.ID] = task
    return task
}

func (s *TaskService) List() []Task {
    s.mu.RLock()
    defer s.mu.RUnlock()
    tasks := make([]Task, 0, len(s.tasks))
    for _, t := range s.tasks {
        tasks = append(tasks, t)
    }
    return tasks
}

func (s *TaskService) Get(id string) (Task, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    task, ok := s.tasks[id]
    return task, ok
}

func (s *TaskService) Update(id string, updated Task) (Task, bool) {
    s.mu.Lock()
    defer s.mu.Unlock()
    task, ok := s.tasks[id]
    if !ok {
        return Task{}, false
    }
    if updated.Title != "" {
        task.Title = updated.Title
    }
    if updated.Description != "" {
        task.Description = updated.Description
    }
    if updated.DueDate != "" {
        task.DueDate = updated.DueDate
    }
    task.Done = updated.Done
    task.UpdatedAt = time.Now()
    s.tasks[id] = task
    return task, true
}

func (s *TaskService) Delete(id string) bool {
    s.mu.Lock()
    defer s.mu.Unlock()
    _, ok := s.tasks[id]
    if ok {
        delete(s.tasks, id)
    }
    return ok
}
"@

Write-File "services/tasks/internal/http/handlers.go" @"
package http

import (
    "encoding/json"
    "net/http"
    "strings"

    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/client/authclient"
    "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/service"
)

type TaskHandler struct {
    taskService *service.TaskService
    authClient  *authclient.Client
}

func NewTaskHandler(ts *service.TaskService, ac *authclient.Client) *TaskHandler {
    return &TaskHandler{
        taskService: ts,
        authClient:  ac,
    }
}

func (h *TaskHandler) verifyToken(w http.ResponseWriter, r *http.Request) bool {
    authHeader := r.Header.Get("Authorization")
    if authHeader == "" {
        http.Error(w, `{"error":"missing authorization header"}`, http.StatusUnauthorized)
        return false
    }
    parts := strings.Split(authHeader, " ")
    if len(parts) != 2 || parts[0] != "Bearer" {
        http.Error(w, `{"error":"invalid authorization header format"}`, http.StatusUnauthorized)
        return false
    }
    token := parts[1]

    valid, _, err := h.authClient.VerifyToken(r.Context(), token)
    if err != nil {
        http.Error(w, `{"error":"authentication service unavailable"}`, http.StatusServiceUnavailable)
        return false
    }
    if !valid {
        http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
        return false
    }
    return true
}

type createTaskRequest struct {
    Title       string `json:"title"`
    Description string `json:"description"`
    DueDate     string `json:"due_date"`
}

type updateTaskRequest struct {
    Title       string `json:"title"`
    Description string `json:"description"`
    DueDate     string `json:"due_date"`
    Done        bool   `json:"done"`
}

type taskResponse struct {
    ID          string `json:"id"`
    Title       string `json:"title"`
    Description string `json:"description"`
    DueDate     string `json:"due_date,omitempty"`
    Done        bool   `json:"done"`
}

func toTaskResponse(t service.Task) taskResponse {
    return taskResponse{
        ID:          t.ID,
        Title:       t.Title,
        Description: t.Description,
        DueDate:     t.DueDate,
        Done:        t.Done,
    }
}

func (h *TaskHandler) CreateTask(w http.ResponseWriter, r *http.Request) {
    if !h.verifyToken(w, r) {
        return
    }

    var req createTaskRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
        return
    }
    if req.Title == "" {
        http.Error(w, `{"error":"title is required"}`, http.StatusBadRequest)
        return
    }

    task := service.Task{
        Title:       req.Title,
        Description: req.Description,
        DueDate:     req.DueDate,
        Done:        false,
    }
    created := h.taskService.Create(task)

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(toTaskResponse(created))
}

func (h *TaskHandler) ListTasks(w http.ResponseWriter, r *http.Request) {
    if !h.verifyToken(w, r) {
        return
    }

    tasks := h.taskService.List()
    resp := make([]taskResponse, len(tasks))
    for i, t := range tasks {
        resp[i] = toTaskResponse(t)
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(resp)
}

func (h *TaskHandler) GetTask(w http.ResponseWriter, r *http.Request) {
    if !h.verifyToken(w, r) {
        return
    }

    id := r.PathValue("id")
    task, ok := h.taskService.Get(id)
    if !ok {
        http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(toTaskResponse(task))
}

func (h *TaskHandler) UpdateTask(w http.ResponseWriter, r *http.Request) {
    if !h.verifyToken(w, r) {
        return
    }

    id := r.PathValue("id")
    var req updateTaskRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
        return
    }

    updatedTask := service.Task{
        Title:       req.Title,
        Description: req.Description,
        DueDate:     req.DueDate,
        Done:        req.Done,
    }
    task, ok := h.taskService.Update(id, updatedTask)
    if !ok {
        http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(toTaskResponse(task))
}

func (h *TaskHandler) DeleteTask(w http.ResponseWriter, r *http.Request) {
    if !h.verifyToken(w, r) {
        return
    }

    id := r.PathValue("id")
    ok := h.taskService.Delete(id)
    if !ok {
        http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)
        return
    }

    w.WriteHeader(http.StatusNoContent)
}
"@

Write-Host "`nProject structure created successfully in folder: $root"
Write-Host "Now you can run the following commands in separate terminals:"
Write-Host ""
Write-Host "  cd $root/services/auth"
Write-Host "  go mod tidy"
Write-Host "  go run ./cmd/auth"
Write-Host ""
Write-Host "  cd $root/services/tasks"
Write-Host "  go mod tidy"
Write-Host "  go run ./cmd/tasks"
Write-Host ""
Write-Host "Make sure to set environment variables if needed:"
Write-Host "  Auth: AUTH_PORT (default 8081)"
Write-Host "  Tasks: TASKS_PORT (default 8082), AUTH_BASE_URL (default http://localhost:8081)"