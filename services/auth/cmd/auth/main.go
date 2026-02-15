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
