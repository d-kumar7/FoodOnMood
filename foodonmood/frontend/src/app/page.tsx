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
