#!/usr/bin/env bash
set -e

echo "=================================================="
echo "🚀 1. INSTALLING SYSTEM DEPENDENCIES & RUNTIMES"
echo "=================================================="

sudo apt-get update -y
sudo apt-get install -y curl git build-essential ca-certificates gnupg lsb-release

if ! command -v docker &> /dev/null; then
  echo "📦 Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo systemctl enable docker
  sudo systemctl start docker

  sudo usermod -aG docker "$USER" || true
  echo "✅ Docker installed successfully."
else
  echo "✅ Docker is already installed."
fi

if ! command -v go &> /dev/null; then
  echo "📦 Installing Go Engine 1.22.3..."
  curl -fsSL https://go.dev/dl/go1.22.3.linux-amd64.tar.gz -o go1.22.3.tar.gz
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.3.tar.gz
  rm go1.22.3.tar.gz

  if ! grep -q '/usr/local/go/bin' ~/.profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
  fi
  export PATH=$PATH:/usr/local/go/bin
  echo "✅ Go engine installed successfully."
else
  echo "✅ Go is already installed."
  export PATH=$PATH:/usr/local/go/bin
fi

if ! command -v node &> /dev/null; then
  echo "📦 Installing Node.js v20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
  echo "✅ Node.js and NPM installed successfully."
else
  echo "✅ Node.js is already installed."
fi

echo "=================================================="
echo "📂 2. SCAFFOLDING DIRECTORY STRUCTURE & FILES"
echo "=================================================="

mkdir -p foodonmood/{frontend/src/app,backend/cmd/api,infrastructure/docker}
cd foodonmood

# --- Database Schema ---
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

# --- Go Backend ---
cat << 'EOF' > backend/go.mod
module foodonmood-backend

go 1.22

require (
	github.com/go-chi/chi/v5 v5.0.12
	github.com/go-chi/cors v1.2.1
	github.com/jackc/pgx/v5 v5.5.5
	github.com/redis/go-redis/v9 v9.5.1
)
EOF

cat << 'EOF' > backend/cmd/api/main.go
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
	dbUser := getEnv("DB_USER", "fom_admin")
	dbPass := getEnv("DB_PASSWORD", "password")
	dbName := getEnv("DB_NAME", "fom_core")

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
EOF

echo "📦 Resolving Go checksums (go.sum)..."
(cd backend && go mod tidy)

cat << 'EOF' > backend/Dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o api ./cmd/api/main.go

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/api .
EXPOSE 8080
CMD ["./api"]
EOF

# --- Next.js Frontend ---
cat << 'EOF' > frontend/package.json
{
  "name": "foodonmood-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "next": "^14.2.3",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/node": "^20.12.12",
    "@types/react": "^18.3.2",
    "typescript": "^5.4.5"
  }
}
EOF

cat << 'EOF' > frontend/next.config.js
/** @type {import('next').NextEncoding} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: process.env.INTERNAL_API_URL 
          ? `${process.env.INTERNAL_API_URL}/:path*`
          : 'http://backend:8080/:path*',
      },
    ]
  },
};

module.exports = nextConfig;
EOF

cat << 'EOF' > frontend/tsconfig.json
{
  "compilerOptions": {
    "target": "es5",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

cat << 'EOF' > frontend/src/app/layout.tsx
import React from "react";

export const metadata = {
  title: "foodonmood",
  description: "Enterprise Containerized Storefront",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body style={{ margin: 0, padding: 0 }}>{children}</body>
    </html>
  );
}
EOF

cat << 'EOF' > frontend/src/app/page.tsx
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
  const [orderMessage, setOrderMessage] = useState<string | null>(null);

  const fetchState = () => {
    Promise.all([
      fetch("/api/products").then((res) => res.json()),
      fetch("/api/cart").then((res) => res.json()),
    ])
      .then(([productsData, cartData]) => {
        setProducts(productsData || []);
        setCart(cartData || {});
      })
      .catch((err) => console.error("Error fetching state:", err))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchState();
  }, []);

  const addToCart = async (sku: string) => {
    await fetch("/api/cart", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ product_id: sku, quantity: 1 }),
    });
    fetchState();
  };

  const handleCheckout = async () => {
    const res = await fetch("/api/checkout", { method: "POST" });
    if (res.ok) {
      setOrderMessage("🎉 Order placed successfully! Your cart has been cleared.");
      fetchState();
      setTimeout(() => setOrderMessage(null), 5000);
    }
  };

  const cartTotalItems = Object.values(cart).reduce((sum, qty) => sum + parseInt(qty, 10), 0);

  const calculateTotal = () => {
    return Object.entries(cart).reduce((total, [sku, qty]) => {
      const prod = products.find((p) => p.sku === sku);
      return total + (prod ? prod.price_cents * parseInt(qty, 10) : 0);
    }, 0);
  };

  if (loading) return <div style={{ padding: "40px", fontFamily: "sans-serif" }}>Loading foodonmood menu...</div>;

  return (
    <main style={{ padding: "40px", fontFamily: "sans-serif", backgroundColor: "#f9fafb", minHeight: "100vh" }}>
      <div style={{ maxWidth: "1000px", margin: "0 auto" }}>
        <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "30px", borderBottom: "1px solid #e5e7eb", paddingBottom: "20px" }}>
          <div>
            <h1 style={{ fontSize: "32px", margin: 0, color: "#111827" }}>foodonmood</h1>
            <p style={{ margin: "5px 0 0 0", color: "#6b7280" }}>Enterprise Containerized Storefront</p>
          </div>
          <div style={{ backgroundColor: "#111827", color: "#fff", padding: "10px 20px", borderRadius: "8px", fontWeight: "bold" }}>
            🛒 Cart: <span style={{ color: "#f97316" }}>{cartTotalItems} items</span>
          </div>
        </header>

        {orderMessage && (
          <div style={{ padding: "15px", backgroundColor: "#d1fae5", border: "1px solid #10b981", borderRadius: "8px", color: "#065f46", marginBottom: "20px", fontWeight: "bold" }}>
            {orderMessage}
          </div>
        )}

        <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: "30px" }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(250px, 1fr))", gap: "20px" }}>
            {products.map((product) => (
              <div key={product.id} style={{ backgroundColor: "#fff", padding: "20px", borderRadius: "12px", border: "1px solid #e5e7eb", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
                <div>
                  <span style={{ fontSize: "12px", fontWeight: "bold", color: "#ea580c", backgroundColor: "#ffedd5", padding: "4px 8px", borderRadius: "4px" }}>
                    {product.sku}
                  </span>
                  <h2 style={{ fontSize: "18px", margin: "10px 0", color: "#111827" }}>{product.name}</h2>
                  <p style={{ color: "#4b5563", fontSize: "14px", lineHeight: "1.5" }}>{product.description}</p>
                </div>

                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: "20px", paddingTop: "15px", borderTop: "1px solid #f3f4f6" }}>
                  <span style={{ fontSize: "20px", fontWeight: "bold" }}>${(product.price_cents / 100).toFixed(2)}</span>
                  <button
                    onClick={() => addToCart(product.sku)}
                    style={{ backgroundColor: "#f97316", color: "#fff", border: "none", padding: "8px 14px", borderRadius: "6px", fontWeight: "bold", cursor: "pointer" }}
                  >
                    Add to Cart
                  </button>
                </div>
              </div>
            ))}
          </div>

          <div style={{ backgroundColor: "#fff", padding: "20px", borderRadius: "12px", border: "1px solid #e5e7eb", height: "fit-content" }}>
            <h2 style={{ fontSize: "20px", margin: "0 0 15px 0", color: "#111827", borderBottom: "1px solid #f3f4f6", paddingBottom: "10px" }}>Order Summary</h2>
            {cartTotalItems === 0 ? (
              <p style={{ color: "#6b7280", fontSize: "14px" }}>Your cart is empty.</p>
            ) : (
              <div>
                {Object.entries(cart).map(([sku, qty]) => {
                  const prod = products.find((p) => p.sku === sku);
                  if (!prod || parseInt(qty, 10) <= 0) return null;
                  return (
                    <div key={sku} style={{ display: "flex", justifyContent: "space-between", marginBottom: "10px", fontSize: "14px" }}>
                      <span>{prod.name} x {qty}</span>
                      <span style={{ fontWeight: "bold" }}>${((prod.price_cents * parseInt(qty, 10)) / 100).toFixed(2)}</span>
                    </div>
                  );
                })}
                <div style={{ borderTop: "1px solid #e5e7eb", marginTop: "15px", paddingTop: "15px", display: "flex", justifyContent: "space-between", fontWeight: "bold", fontSize: "18px" }}>
                  <span>Total:</span>
                  <span>${(calculateTotal() / 100).toFixed(2)}</span>
                </div>
                <button
                  onClick={handleCheckout}
                  style={{ width: "100%", marginTop: "20px", backgroundColor: "#10b981", color: "#fff", border: "none", padding: "12px", borderRadius: "8px", fontWeight: "bold", fontSize: "16px", cursor: "pointer" }}
                >
                  Checkout
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </main>
  );
}
EOF

cat << 'EOF' > frontend/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/next.config.js ./next.config.js

EXPOSE 3000
CMD ["npm", "run", "start"]
EOF

# --- Docker Compose Manifest ---
cat << 'EOF' > docker-compose.yml
services:
  postgres:
    image: postgres:16-alpine
    container_name: foodonmood-db
    environment:
      POSTGRES_USER: fom_admin
      POSTGRES_PASSWORD: password
      POSTGRES_DB: fom_core
    ports:
      - "5433:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./infrastructure/docker/schema.sql:/docker-entrypoint-initdb.d/schema.sql
    networks:
      - foodonmood_net
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: foodonmood-cache
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - foodonmood_net
    restart: unless-stopped

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: foodonmood-api
    environment:
      DB_HOST: postgres
      DB_PORT: 5432
      DB_USER: fom_admin
      DB_PASSWORD: password
      DB_NAME: fom_core
      REDIS_HOST: redis
      REDIS_PORT: 6379
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - redis
    networks:
      - foodonmood_net
    restart: unless-stopped

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: foodonmood-ui
    environment:
      INTERNAL_API_URL: http://backend:8080
    ports:
      - "3000:3000"
    depends_on:
      - backend
    networks:
      - foodonmood_net
    restart: unless-stopped

networks:
  foodonmood_net:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
EOF

echo "=================================================="
echo "⚡ 3. DEPLOYING CONTAINERS"
echo "=================================================="

sudo docker compose build --no-cache
sudo docker compose up -d

echo ""
echo "=================================================="
echo "🎉 DEPLOYMENT COMPLETE!"
echo "=================================================="
echo "Frontend Storefront: http://localhost:3000"
echo "Backend REST API:    http://localhost:8080"
echo "PostgreSQL Port:     5433"
echo "Redis Port:          6379"
echo "=================================================="
