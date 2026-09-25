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
