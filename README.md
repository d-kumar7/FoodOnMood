# 🍲 foodonmood — Enterprise Containerized Microservices Platform
Your Mood Our Food
 
[![Docker](https://img.shields.io/badge/Docker-24.0+-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![Go](https://img.shields.io/badge/Go-1.22-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://go.dev/)
[![Next.js](https://img.shields.io/badge/Next.js-14.2-000000?style=for-the-badge&logo=nextdotjs&logoColor=white)](https://nextjs.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7-DC382D?style=for-the-badge&logo=redis&logoColor=white)](https://redis.io/)

> A high-performance, containerized full-stack e-commerce architecture built with Next.js App Router, Go (Chi API Framework), PostgreSQL, and Redis cache.

## 🏛 System Architecture & Traffic Flow
```
                              [ USER BROWSER ]
                                     │
                                     │ (HTTP Port 3000)
                                     ▼
                        ┌────────────────────────┐
                        │   Frontend Container   │
                        │      (Next.js 14)      │
                        └────────────┬───────────┘
                                     │
                                     │ Internal Docker Proxy (/api/*)
                                     ▼
                        ┌────────────────────────┐
                        │   Backend REST API     │
                        │    (Go 1.22 + Chi)     │
                        └─────┬────────────┬─────┘
                              │            │
         SQL Queries (5432)   │            │ Redis Hash Commands (6379)
                              ▼            ▼
                 ┌────────────────┐    ┌────────────────┐
                 │ PostgreSQL 16  │    │    Redis 7     │
                 │  (Persistent)  │    │ (Session/Cart) │
                 └────────────────┘    └────────────────┘

```

## 🎨 UI Layout & Storefront Design

```
+-------------------------------------------------------------------------------+
| 🍲 foodonmood               Enterprise Storefront            🛒 Cart: 3 items|
+-------------------------------------------------------------------------------+
|                                                                               |
|  [ MENU ITEMS ]                                   [ ORDER SUMMARY ]           |
|  +-----------------------------------------+      +------------------------+  |
|  | MEAL-001                                |      | Spicy Paneer Tikka x 2 |  |
|  | Spicy Paneer Tikka                      |      | $70.00                 |  |
|  | Classic paneer with spices              |      |                        |  |
|  | $35.00                   [Add to Cart]  |      | Butter Chicken x 1     |  |
|  +-----------------------------------------+      | $45.00                 |  |
|  +-----------------------------------------+      | ---------------------- |  |
|  | MEAL-002                                |      | Total: $115.00         |  |
|  | Butter Chicken                          |      |                        |  |
|  | Tender chicken and garlic naan          |      | [   CHECKOUT NOW   ]   |  |
|  | $45.00                   [Add to Cart]  |      |                        |  |
|  +-----------------------------------------+      +------------------------+  |
+-------------------------------------------------------------------------------+
```

## 🚀 Key Features

* **Zero-Configuration Automated Deployment:** Complete setup, dependency checks, file scaffolding, and build via a single `./setup.sh` execution.
* **Optimized Docker Multi-Stage Builds:** Light alpine production images optimized for minimal resource footprints.
* **Internal Network Reverse Proxying:** Frontend server seamlessly routes dynamic `/api/*` traffic across the internal Docker bridge without expose issues.
* **Resilient Database Auto-Healing:** Go API incorporates retries and backoff logic to ensure smooth startup ordering over PostgreSQL and Redis dependencies.
* **Persistent In-Memory Session Caching:** Lightning-fast shopping cart persistence powered by key-value hashing via Redis.


## 📊 Container Services & Network Exposure
```
| Service Name | Technology Stack | Host Port | Internal Container Port | Function |
| :--- | :--- | :--- | :--- | :--- |
| **`foodonmood-ui`** | Next.js 14 / TypeScript | `3000` | `3000` | Web Storefront & Reverse Proxy |
| **`foodonmood-api`** | Go 1.22 / Chi Framework | `8080` | `8080` | REST API Engine & Data Layer |
| **`foodonmood-db`** | PostgreSQL 16 | `5433` | `5432` | Product Catalog Data Persistence |
| **`foodonmood-cache`**| Redis 7 | `6379` | `6379` | High-Speed In-Memory Cart Storage |

```
## 🛠 Quick Start Guide

### Prerequisites
Make sure your environment meets the following requirements:
* **Operating System:** Ubuntu 22.04/26.04.1 LTS, Debian, or WSL2
* **Permissions:** `sudo` privileges for package/Docker orchestration

### One-Step Automated Setup

1. Clone the repository and navigate into the target workspace:
   ```bash
   git clone [https://github.com/d-kumar7/foodonmood.git](https://github.com/d-kumar7/foodonmood.git)
   ```
Give execution permissions to the automated installer:
```Bash
chmod +x FoodOnMood
```
Run the orchestration script:
```Bash
./FoodOnMood
```
```
📡 Core API EndpointsMethodEndpointDescriptionSample Payload / OutputGET/API Status & Base Check{"service": "foodonmood backend API", "status": "online"}GET/healthLiveness / Readiness Probefoodonmood enterprise API is highly availableGET/productsFetch Product Catalog[{"sku": "MEAL-001", "name": "Spicy Paneer Tikka", "price_cents": 3500}]GET/cartGet Active User Session Cart{"MEAL-001": "2", "MEAL-002": "1"}POST/cartIncrement Item Quantity{"product_id": "MEAL-001", "quantity": 1}POST/checkoutProcess Order & Clear Cart{"status": "success", "message": "Order placed successfully!"}🔍 Verification & Health InspectionVerify service states directly from your shell:
```
```Bash
# Check running containers
docker compose ps
# Check database readiness
docker exec -it foodonmood-db pg_isready -U foodonmood_admin -d foodonmood_core
# Test backend API connectivity
curl -i http://localhost:8080/health
# Inspect Redis cache state
docker exec -it foodonmood-cache redis-cli KEYS "*"
```
📁 Repository Directory StructurePlaintextfoodonmood/
```
├── backend/
│   ├── cmd/
│   │   └── api/
│   │       └── main.go          # Go Chi API Server & Route Definitions
│   ├── Dockerfile               # Multi-stage Go Binary Build Context
│   ├── go.mod                   # Dependency Definitions
│   └── go.sum                   # Checksum Integrity Module
├── frontend/
│   ├── src/
│   │   └── app/
│   │       ├── layout.tsx       # Next.js App Router Master Layout
│   │       └── page.tsx         # Interactive React Storefront UI
│   ├── Dockerfile               # Production Next.js Image Config
│   ├── next.config.js           # Internal API Proxy Engine Settings
│   └── package.json             # Node.js Module Dependencies
├── infrastructure/
│   └── docker/
│       └── schema.sql           # Database Initialization & Seed Data
├── docker-compose.yml           # Unified Container Orchestration Manifest
└── setup.sh                     # Automated Environment Installer Script
```
📄 License
<p>Distributed under the [MIT]() License. See LICENSE for details.</p>
