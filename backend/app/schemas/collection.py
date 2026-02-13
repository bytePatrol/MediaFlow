from typing import Optional, List
from pydantic import BaseModel


class CollectionInfo(BaseModel):
    id: str
    title: str
    section_key: str
    section_title: str
    item_count: int = 0
    thumb_url: Optional[str] = None


class CollectionCreateRequest(BaseModel):
    server_id: int
    library_id: int
    title: str
    media_item_ids: List[int]


class CollectionAddRequest(BaseModel):
    server_id: int
    media_item_ids: List[int]


class CollectionCreateResponse(BaseModel):
    status: str
    collection_id: Optional[str] = None
    title: str
    items_added: int
