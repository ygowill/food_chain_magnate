from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.db import init_db
from app.auth import router as auth_router
from app.device_auth import router as device_auth_router
from app.rooms import router as rooms_router
from app.matches import router as matches_router
from app.internal import router as internal_router
from app.admin import router as admin_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(title="FCM Platform Backend", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.web_origin],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(device_auth_router)
app.include_router(rooms_router)
app.include_router(matches_router)
app.include_router(internal_router)
app.include_router(admin_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
