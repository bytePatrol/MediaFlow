from pydantic import BaseModel
from typing import Optional, List


class TagBrief(BaseModel):
    id: int
    name: str
    color: str

    model_config = {"from_attributes": True}


class TagResponse(BaseModel):
    id: int
    name: str
    color: str
    media_count: int = 0

    model_config = {"from_attributes": True}


class TagCreate(BaseModel):
    name: str
    color: str = "#256af4"


class TagUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None


class BulkTagRequest(BaseModel):
    media_item_ids: List[int]
    tag_ids: List[int]


class BulkTagRemoveRequest(BaseModel):
    media_item_ids: List[int]
    tag_ids: List[int]
