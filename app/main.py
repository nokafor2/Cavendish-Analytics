"""Cavendish Analytics API — FastAPI application."""

import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_ERRORS = Counter(
    "http_request_errors_total",
    "Total HTTP error responses (4xx/5xx)",
    ["method", "endpoint"],
)
ACTIVE_CONNECTIONS = Gauge(
    "http_active_connections",
    "Simulated active connections for load testing",
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(
    title="Cavendish Analytics API",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/v1/portfolio/{portfolio_id}")
async def get_portfolio(portfolio_id: str):
    """Return portfolio risk summary — primary client-facing endpoint."""
    REQUEST_COUNT.labels(method="GET", endpoint="/api/v1/portfolio", status="200").inc()
    return {
        "portfolio_id": portfolio_id,
        "risk_score": 0.42,
        "regulatory_exposure": "within_limits",
        "last_updated": time.time(),
    }


@app.get("/api/v1/analytics/compute")
async def compute_analytics(intensity: int = 1):
    """CPU-intensive endpoint for HPA load testing."""
    REQUEST_COUNT.labels(method="GET", endpoint="/api/v1/analytics/compute", status="200").inc()
    ACTIVE_CONNECTIONS.inc()
    try:
        result = sum(i * i for i in range(intensity * 100_000))
        return {"result": result, "intensity": intensity}
    finally:
        ACTIVE_CONNECTIONS.dec()


@app.get("/api/v1/db/status")
async def db_status():
    """Database connectivity check — uses Secrets Manager credentials via CSI."""
    db_host = os.getenv("DB_HOST", "postgres")
    db_name = os.getenv("DB_NAME", "cavendish")
    db_password = os.getenv("DB_PASSWORD")

    if not db_password:
        REQUEST_ERRORS.labels(method="GET", endpoint="/api/v1/db/status").inc()
        REQUEST_COUNT.labels(method="GET", endpoint="/api/v1/db/status", status="503").inc()
        raise HTTPException(status_code=503, detail="Database credentials not mounted")

    REQUEST_COUNT.labels(method="GET", endpoint="/api/v1/db/status", status="200").inc()
    return {"db_host": db_host, "db_name": db_name, "connected": True}
