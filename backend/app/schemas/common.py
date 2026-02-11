from pydantic import BaseModel
from typing import Optional, List, Generic, TypeVar
from datetime import datetime

T = TypeVar("T")


class StatusResponse(BaseModel):
    status: str
    message: str


class PaginatedResponse(BaseModel, Generic[T]):
    items: List[T]
    total: int
    page: int
    page_size: int
    total_pages: int


class WebSocketMessage(BaseModel):
    event: str
    timestamp: datetime
    data: dict
