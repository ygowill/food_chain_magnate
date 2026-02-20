from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.db import init_db
from app.auth import router as auth_router
from app.rooms import router as rooms_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(title="FCM Platform Backend", lifespan=lifespan)
app.include_router(auth_router)
app.include_router(rooms_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
