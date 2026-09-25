


# Install Docker on Ubuntu
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
Executing docker install script, commit: 7cae5f8b0decc17d6571f9f52eb840fbc13b2737
<...>
```

# Phase - I
<P>frontend # Tier 1: Next.js web application
backend/cmd/api # Tier 2: Go microservices entrypoint
backend/internal # Tier 2: Go Clean Architecture domains
infrastructure/docker # Tier 3: Local container orchestration
infrastructure/aws # Cloud IaC (Terraform/CloudFormation)
scripts # Automation and deployment bash scripts
</P>

<h3>  Scaffold the 3-tier architecture directories </h3>

```bash
mkdir foodonmood
cd foodonmood
mkdir -p {frontend,backend/cmd/api,backend/internal,infrastructure/docker,infrastructure/aws,scripts}
git init
cat << 'EOF' > README.md
# foodonmood - For All Visitors
## Enterprise E-Commerce Architecture
### Directory Structure Overview
- **frontend/**: Tier 1 - Next.js web application
- **backend/cmd/api/**: Tier 2 - Go microservices entrypoint
- **backend/internal/**: Tier 2 - Go Clean Architecture domains
- **infrastructure/docker/**: Tier 3 - Local container orchestration
- **infrastructure/aws/**: Cloud IaC (Terraform/CloudFormation)
- **scripts/**: Automation and deployment shell scripts
### Local Data Tier (Docker)
The `docker-compose.yml` file simulates the AWS data layer:
1. **PostgreSQL 16**: Primary relational database simulating AWS RDS for users, products, and orders.
2. **Redis 7**: In-memory cache simulating AWS ElastiCache for high-speed shopping cart state.
EOF
cat << 'EOF' > infrastructure/docker/docker-compose.yml
version: '3.8'
services:
 postgres:
 image: postgres:16-alpine
 container_name: foodonmood-db
 environment:
 POSTGRES_USER: foodonmood_admin
 POSTGRES_PASSWORD: secretpassword
 POSTGRES_DB: foodonmood_core
 ports:
 - "5432:5432"
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
cd infrastructure/docker
docker compose up -d
cd ../..
```

# To build the Tier 2 Application layer so it can establish a connection to your PostgreSQL and Redis containers.
<p>
# Execute these commands in your terminal to initialize the Go module, install the enterprise routing and database drivers, and scaffold the primary API entry point:
</p>

```bash
# Navigate to the backend directory and initialize the Go module
cd backend
go mod init foodonmood-backend
# Install the Chi router, PostgreSQL driver (pgx), and Redis client
go get github.com/go-chi/chi/v5
go get github.com/jackc/pgx/v5/pgxpool
go get github.com/redis/go-redis/v9
# Create the main API entrypoint with database and cache connection logic
cat << 'EOF' > cmd/api/main.go
package main
import (
"context"
"fmt"
"log"
"net/http"
"os"
"os/signal"
"syscall"
"time"
"github.com/go-chi/chi/v5"
"github.com/go-chi/chi/v5/middleware"
"github.com/jackc/pgx/v5/pgxpool"
"github.com/redis/go-redis/v9"
)
func main() {
ctx := context.Background()
// 1. Initialize PostgreSQL Connection Pool
dbURL := "postgres://foodonmood_admin:secretpassword@localhost:5432/foodonmood_core"
dbPool, err := pgxpool.New(ctx, dbURL)
if err != nil {
log.Fatalf("Unable to connect to PostgreSQL: %v\n", err)
}
defer dbPool.Close()
if err := dbPool.Ping(ctx); err != nil {
log.Fatalf("PostgreSQL ping failed: %v\n", err)
}
fmt.Println("✅ Connected to PostgreSQL (foodonmood_core)")
// 2. Initialize Redis Client
rdb := redis.NewClient(&redis.Options{
Addr: "localhost:6379",
})
defer rdb.Close()
if err := rdb.Ping(ctx).Err(); err != nil {
log.Fatalf("Redis ping failed: %v\n", err)
}
fmt.Println("✅ Connected to Redis (Shopping Cart Cache)")
// 3. Configure the Chi Router
r := chi.NewRouter()
r.Use(middleware.Logger)
r.Use(middleware.Recoverer)
r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
w.WriteHeader(http.StatusOK)
w.Write([]byte("foodonmood enterprise API is highly available"))
})
// 4. Start the HTTP Server with Graceful Shutdown
srv := &http.Server{
Addr: ":8080",
Handler: r,
}
go func() {
fmt.Println("🚀 foodonmood API running on port 8080")
if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
log.Fatalf("Server failed to start: %v\n", err)
}
}()
// Wait for interrupt signal to gracefully shut down the server
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
<-quit
fmt.Println("\nShutting down server...")
ctxShutDown, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
if err := srv.Shutdown(ctxShutDown); err != nil {
log.Fatalf("Server Shutdown Failed:%+v", err)
}
fmt.Println("Server exited properly")
}
EOF
# Run the API to test the connections
go run cmd/api/main.go
```

<p> # If everything is configured correctly, you will see green checkmarks confirming the Go API has successfully pinged both the PostgreSQL database and the Redis cache, followed by the port 8080 startup message. To verify the router is working, you can open a new terminal tab and run `curl</p>

```bash
cd ../infrastructure/docker
# Destroy the old setup
docker compose down -v
# Update the Docker Compose file to use port 5433 on the host
sed -i '' 's/"5432:5432"/"5433:5432"/g' docker-compose.yml
# Spin it back up
docker compose up -d
cd ../../backend
# Update the Go database connection string to point to 5433
sed -i '' 's/localhost:5432/localhost:5433/g' cmd/api/main.go
# Wait 5 seconds to ensure Postgres finishes its first-boot initialization
sleep 5
# Run the API again
go run cmd/api/main.go
```
<p>
# You should now see those green checkmarks confirming successful connections to both PostgreSQL and Redis. Once that works, we can move on to scaffolding the Next.js frontend!
# Leave this terminal running in the background—your Go API and database connections are perfectly healthy.
# Open a new terminal tab to scaffold the Tier 1 Presentation Layer. We will use Next.js with the App Router, TypeScript, and Tailwind CSS to build the frontend, and immediately wire it up to ping your Go API.
</p>

# Run these commands in the new tab:

```bash
# Navigate to the frontend directory you created earlier
cd ~/Shared/project/DevOps/foodonmood/frontend
# Scaffold the Next.js app directly into this directory
npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --import-alias "@/*" --use-n
# Overwrite the default homepage to test the connection to your Go API
cat << 'EOF' > src/app/page.tsx
export default async function Home() {
 // Fetch the health check from the Go API
 const res = await fetch('http://localhost:8080/health', { cache: 'no-store' });
 const backendStatus = res.ok ? await res.text() : 'API offline';
 return (
 <main className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-10">
 <div className="bg-white p-8 rounded-xl shadow-sm border border-gray-200 max-w-md w-full text-center
 <h1 className="text-3xl font-black text-gray-900 mb-2">foodonmood</h1>
 <p className="text-gray-500 mb-8 font-medium">Enterprise E-Commerce Platform</p>
 
 <div className="bg-gray-900 rounded-lg p-4 font-mono text-sm text-left text-green-400">
 <span className="text-gray-400"># API Health Check</span>
 <br />
 {backendStatus}
 </div>
 </div>
 </main>
 );
}
EOF
# Start the Next.js development server
npm run dev
```

Once the terminal says Ready in x ms, open your browser and navigate to http://localhost:3000.
You should see the foodonmood branding alongside a green terminal box displaying the health check string coming directly from your Go
backend. Let me know when you see it on your screen!
