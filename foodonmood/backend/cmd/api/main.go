package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type Product struct {
	ID            string `json:"id"`
	SKU           string `json:"sku"`
	Name          string `json:"name"`
	Description   string `json:"description"`
	PriceCents    int    `json:"price_cents"`
	StockQuantity int    `json:"stock_quantity"`
}

type CartItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func main() {
	ctx := context.Background()

	dbHost := getEnv("DB_HOST", "postgres")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "foodonmood_admin")
	dbPass := getEnv("DB_PASSWORD", "secretpassword")
	dbName := getEnv("DB_NAME", "foodonmood_core")

	redisHost := getEnv("REDIS_HOST", "redis")
	redisPort := getEnv("REDIS_PORT", "6379")

	dbURL := fmt.Sprintf("postgres://%s:%s@%s:%s/%s", dbUser, dbPass, dbHost, dbPort, dbName)
	
	var dbPool *pgxpool.Pool
	var err error
	
	for i := 0; i < 10; i++ {
		dbPool, err = pgxpool.New(ctx, dbURL)
		if err == nil {
			err = dbPool.Ping(ctx)
			if err == nil {
				break
			}
		}
		log.Println("Waiting for database connection...")
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		log.Fatalf("Could not connect to database: %v\n", err)
	}
	defer dbPool.Close()

	rdb := redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
	})
	defer rdb.Close()

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "online", "service": "foodonmood backend API"}`))
	})

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("foodonmood enterprise API is highly available"))
	})

	r.Get("/products", func(w http.ResponseWriter, r *http.Request) {
		reqCtx := r.Context()
		rows, err := dbPool.Query(reqCtx, "SELECT id, sku, name, description, price_cents, stock_quantity FROM products")
		if err != nil {
			http.Error(w, "Failed to query products", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		var products []Product
		for rows.Next() {
			var p Product
			if err := rows.Scan(&p.ID, &p.SKU, &p.Name, &p.Description, &p.PriceCents, &p.StockQuantity); err != nil {
				http.Error(w, "Failed to scan product", http.StatusInternalServerError)
				return
			}
			products = append(products, p)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(products)
	})

	r.Post("/cart", func(w http.ResponseWriter, r *http.Request) {
		sessionID := "user-session-123"
		var item CartItem
		if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
			http.Error(w, "Invalid request payload", http.StatusBadRequest)
			return
		}

		err := rdb.HIncrBy(ctx, "cart:"+sessionID, item.ProductID, int64(item.Quantity)).Err()
		if err != nil {
			http.Error(w, "Failed to update cart", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "item added to cart"}`))
	})

	r.Get("/cart", func(w http.ResponseWriter, r *http.Request) {
		sessionID := "user-session-123"
		cart, err := rdb.HGetAll(ctx, "cart:"+sessionID).Result()
		if err != nil {
			http.Error(w, "Failed to fetch cart", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(cart)
	})

	r.Post("/checkout", func(w http.ResponseWriter, r *http.Request) {
		sessionID := "user-session-123"
		err := rdb.Del(ctx, "cart:"+sessionID).Err()
		if err != nil {
			http.Error(w, "Failed to process checkout", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "success", "message": "Order placed successfully!"}`))
	})

	srv := &http.Server{
		Addr:    ":8080",
		Handler: r,
	}

	go func() {
		fmt.Println("foodonmood API running on port 8080")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v\n", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctxShutDown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctxShutDown); err != nil {
		log.Fatalf("Server Shutdown Failed:%+v", err)
	}
}
