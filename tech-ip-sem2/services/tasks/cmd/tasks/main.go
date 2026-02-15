package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/shared/middleware"
	"github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/client/authclient"
	handlers "github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/http"
	"github.com/sun1tar/MIREA-TIP-Practice-17/tech-ip-sem2/tasks/internal/service"
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
	taskHandler := handlers.NewTaskHandler(taskService, authClient)

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
