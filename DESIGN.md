# foodonmood — Enterprise 3-Tier E-Commerce Blueprint

A production-grade, dynamic 3-tier enterprise e-commerce web application engineered for high availability, microservice decoupling, and cloud-native Kubernetes deployment via GitOps.

---

## 📐 Enterprise System Architecture


                   ┌────────────────────────────────────────┐
                   │          Client Browser (UI)           │
                   └───────────────────┬────────────────────┘
                                       │
                                 HTTP / Port 8080
                                       │
                                       ▼
                   ┌────────────────────────────────────────┐
                   │   Presentation Tier (Next.js 14 SSR)   │
                   └───────────────────┬────────────────────┘
                                       │
                             JSON REST API Requests
                                       │
                                       ▼
                   ┌────────────────────────────────────────┐
                   │   Application Tier (Go REST Service)   │
                   └──────────────┬─────────────────┬───────┘
                                  │                 │
                     SQL Queries  │                 │ Session / Cart Ops
                     Port 5433    │                 │ Port 6379
                                  ▼                 ▼
         ┌──────────────────────────────┐     ┌──────────────────────────────┐
         │   PostgreSQL 16 Database     │     │      Redis 7 Cache           │
         │     (Data Tier - Core)       │     │    (Data Tier - In-Mem)      │
         └──────────────────────────────┘     └──────────────────────────────┘


The system operates across three strictly segregated tiers:
* **Tier 1 (Presentation):** Next.js 14 Web Application utilizing Tailwind CSS and React Server Components.
* **Tier 2 (Application):** Go API built with Clean Architecture, utilizing `chi` router for high-throughput REST endpoints.
* **Tier 3 (Data & Cache):** PostgreSQL 16 for transactional persistence (users, inventory, orders) and Redis 7 for high-speed, low-latency cart operations.

---

## 📂 Repository Directory Layout

```
foodonmood/
├── backend/                  # Tier 2 Application (Go Microservices)
│   ├── cmd/
│   │   └── api/
│   │       └── main.go       # Go API Entrypoint with PostgreSQL & Redis Drivers
│   ├── go.mod                # Go module dependencies
│   └── go.sum                # Dependency checksums
├── frontend/                 # Tier 1 Presentation (Next.js 14)
│   ├── src/
│   │   └── app/
│   │       └── page.tsx      # Dynamic E-Commerce Storefront
│   ├── package.json
│   └── tailwind.config.ts
├── infrastructure/           # Infrastructure & Deployment Manifests
│   └── docker/
│       ├── docker-compose.yml# Local Tier 3 Data Tier Orchestration
│       └── schema.sql        # Database initialization script
└── scripts/                  # Shell automation & setup scripts
```

## ⚡ Quickstart & Local Setup Guide

Follow these steps to deploy and target the `foodonmood` enterprise platform on an **Ubuntu VM** or local environment.

### Prerequisites
* **Ubuntu OS:** Ubuntu 22.04 LTS or 24.04 LTS recommended.
* **Docker & Docker Compose:** Container runtime installed and enabled.
* **Go Engine:** Go version 1.22+ installed.
* **Node.js Environment:** Node.js v20+ and `npm` installed.



### Step 1: System Dependencies & Repository Setup

Initialize system packages and set up your target working directory:

```bash
# Update system packages
sudo apt update && sudo apt install -y curl git build-essential

# Navigate to project working directory
mkdir -p ~/foodonmood
cd ~/foodonmood
# Scaffold project tree
mkdir -p {frontend,backend/cmd/api,backend/internal,infrastructure/docker,infrastructure/aws,scripts}
```
Step 2: Provision Data Tier (PostgreSQL & Redis)
Provision the containerized database and cache layer via Docker Compose:

```Bash
cat << 'EOF' > infrastructure/docker/docker-compose.yml
services:
  postgres:
    image: postgres:16-alpine
    container_name: foodonmood-db
    environment:
      POSTGRES_USER: foodonmood_admin
      POSTGRES_PASSWORD: secretpassword
      POSTGRES_DB: foodonmood_core
    ports:
      - "5433:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - foodonmood_network
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: foodonmood-cache
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - foodonmood_network
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:

networks:
  foodonmood_network:
    driver: bridge
EOF

# Spin up data containers
cd infrastructure/docker
docker compose up -d
cd ../..
```
Step 3: Seed PostgreSQL Schema & Starter Inventory
Apply relational schema and sample food items directly into the running database container:

```Bash
cat << 'EOF' > infrastructure/docker/schema.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price_cents INT NOT NULL,
    stock_quantity INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (sku, name, description, price_cents, stock_quantity)
VALUES 
    ('MEAL-001', 'Spicy Paneer Tikka', 'Classic paneer with spices', 3500, 50),
    ('MEAL-002', 'Butter Chicken', 'Tender chicken and garlic naan', 4500, 30),
    ('MEAL-003', 'Vegan Buddha Bowl', 'Quinoa, tofu, and greens', 2990, 20)
ON CONFLICT (sku) DO NOTHING;
EOF

# Execute schema injection
docker cp infrastructure/docker/schema.sql foodonmood-db:/schema.sql
docker exec foodonmood-db psql -U foodonmood_admin -d foodonmood_core -f /schema.sql
```
Step 4: Provision Tier 2 Backend API (Go)
Initialize the Go REST backend service equipped with CORS support for seamless client browser communication:

```Bash
cd backend
go mod init foodonmood-backend
go get [github.com/go-chi/chi/v5](https://github.com/go-chi/chi/v5)
go get [github.com/go-chi/cors](https://github.com/go-chi/cors)
go get [github.com/jackc/pgx/v5/pgxpool](https://github.com/jackc/pgx/v5/pgxpool)
go get [github.com/redis/go-redis/v9](https://github.com/redis/go-redis/v9)

cat << 'EOF' > cmd/api/main.go
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

	"[github.com/go-chi/chi/v5](https://github.com/go-chi/chi/v5)"
	"[github.com/go-chi/chi/v5/middleware](https://github.com/go-chi/chi/v5/middleware)"
	"[github.com/go-chi/cors](https://github.com/go-chi/cors)"
	"[github.com/jackc/pgx/v5/pgxpool](https://github.com/jackc/pgx/v5/pgxpool)"
	"[github.com/redis/go-redis/v9](https://github.com/redis/go-redis/v9)"
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

func main() {
	ctx := context.Background()

	dbURL := "postgres://foodonmood_admin:secretpassword@localhost:5433/foodonmood_core"
	dbPool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("Unable to connect to PostgreSQL: %v\n", err)
	}
	defer dbPool.Close()

	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
	})
	defer rdb.Close()

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"http://localhost:3000", "http://localhost:3001", "*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

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
EOF

# Start the Go Application Layer
go run cmd/api/main.go &
cd ..
```
Step 5: Provision Tier 1 Presentation Layer (Next.js 14)
Scaffold and build the dynamic web user interface:

```Bash
cd frontend

cat << 'EOF' > src/app/page.tsx
"use client";

import { useEffect, useState } from "react";

type Product = {
  id: string;
  sku: string;
  name: string;
  description: string;
  price_cents: number;
  stock_quantity: number;
};

export default function Home() {
  const [products, setProducts] = useState<Product[]>([]);
  const [cart, setCart] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      fetch("http://localhost:8080/products").then((res) => res.json()),
      fetch("http://localhost:8080/cart").then((res) => res.json()),
    ])
      .then(([productsData, cartData]) => {
        setProducts(productsData || []);
        setCart(cartData || {});
      })
      .finally(() => setLoading(false));
  }, []);

  const addToCart = async (sku: string) => {
    await fetch("http://localhost:8080/cart", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ product_id: sku, quantity: 1 }),
    });

    const res = await fetch("http://localhost:8080/cart");
    const updatedCart = await res.json();
    setCart(updatedCart || {});
  };

  const cartTotalItems = Object.values(cart).reduce((sum, qty) => sum + parseInt(qty), 0);

  if (loading) return <div className="min-h-screen flex items-center justify-center">Loading foodonmood menu...</div>;

  return (
    <main className="min-h-screen bg-gray-50 p-10 font-sans">
      <div className="max-w-6xl mx-auto">
        <header className="mb-12 flex justify-between items-center border-b pb-6">
          <div>
            <h1 className="text-4xl font-black text-gray-900">foodonmood</h1>
            <p className="text-gray-500 font-medium">Enterprise E-Commerce Menu</p>
          </div>
          <div className="bg-gray-900 text-white px-6 py-3 rounded-lg font-bold flex items-center gap-3 shadow-md">
            <span>🛒 Cart</span>
            <span className="bg-orange-500 px-3 py-1 rounded-md text-sm">{cartTotalItems} items</span>
          </div>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {products.map((product) => (
            <div key={product.id} className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex flex-col justify-between">
              <div>
                <div className="flex justify-between items-start mb-4">
                  <span className="text-xs font-bold text-orange-600 bg-orange-50 px-2 py-1 rounded-md tracking-wider">
                    {product.sku}
                  </span>
                  <span className="text-xs font-medium text-green-700 bg-green-50 px-2 py-1 rounded-md">
                    {cart[product.sku] ? `${cart[product.sku]} in cart` : "0 in cart"}
                  </span>
                </div>
                <h2 className="text-2xl font-bold text-gray-900 mb-2">{product.name}</h2>
                <p className="text-gray-600 mb-6 text-sm leading-relaxed">{product.description}</p>
              </div>

              <div className="flex justify-between items-center border-t pt-5 mt-auto">
                <div className="text-3xl font-black text-gray-900">
                  ${(product.price_cents / 100).toFixed(2)}
                </div>
                <button
                  onClick={() => addToCart(product.sku)}
                  className="bg-orange-500 text-white px-5 py-2.5 rounded-lg font-bold hover:bg-orange-600 transition-colors"
                >
                  Add to Cart
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}
EOF

# Launch Next.js dev server
npm run dev
```
🚀 Verification & Endpoint Access
Once deployed, access and verify the platform using the following standard endpoints:

Layer	Service	Endpoint	Verification Command
Tier 1	Next.js Storefront	http://localhost:3000	Access via Browser
Tier 2	API Health Status	http://localhost:8080/health	curl http://localhost:8080/health
Tier 2	Product Catalog API	http://localhost:8080/products	curl http://localhost:8080/products
Tier 2	Redis Cart API	http://localhost:8080/cart	curl http://localhost:8080/cart
Tier 3	PostgreSQL DB	localhost:5433	docker exec -it foodonmood-db psql -U foodonmood_admin -d foodonmood_core
Tier 3	Redis Cache	localhost:6379	docker exec -it foodonmood-cache redis-cli ping
