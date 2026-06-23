import os
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

DB_HOST = os.environ.get("DB_HOST", "postgres-service")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")

_password_file = os.environ.get("DB_PASSWORD_FILE", "/secrets/db-password")
if os.path.exists(_password_file):
    with open(_password_file, encoding="utf-8") as f:
        DB_PASSWORD = f.read().strip()
else:
    DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

connection_pool: pool.ThreadedConnectionPool | None = None


def get_pool() -> pool.ThreadedConnectionPool:
    if connection_pool is None:
        raise RuntimeError("Database connection pool is not initialized")
    return connection_pool


@asynccontextmanager
async def lifespan(_: FastAPI):
    global connection_pool
    connection_pool = pool.ThreadedConnectionPool(
        minconn=1,
        maxconn=10,
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )
    yield
    if connection_pool is not None:
        connection_pool.closeall()
        connection_pool = None


app = FastAPI(title="Assignment API", version="1.0.0", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, str]:
    conn = None
    try:
        conn = get_pool().getconn()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        return {"status": "healthy", "database": "connected"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unavailable: {exc}") from exc
    finally:
        if conn is not None:
            get_pool().putconn(conn)


@app.get("/api/products")
def list_products() -> dict[str, Any]:
    conn = None
    try:
        conn = get_pool().getconn()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id, name, category, price, stock FROM products ORDER BY id"
            )
            rows = cur.fetchall()
        return {"count": len(rows), "products": rows}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    finally:
        if conn is not None:
            get_pool().putconn(conn)


@app.get("/")
def root() -> dict[str, str]:
    return {
        "service": "assignment-api",
        "endpoints": "/health, /api/products",
    }
