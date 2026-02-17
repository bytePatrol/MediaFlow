from sqlalchemy import Column, Integer, String, Boolean, JSON, DateTime, func
from app.database import Base


class AutomationRule(Base):
    __tablename__ = "automation_rules"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(200), nullable=False)
    is_enabled = Column(Boolean, default=True)
    trigger_type = Column(String(50), nullable=False)  # analysis_complete, job_complete, job_failed, library_sync, storage_threshold, schedule
    conditions_json = Column(JSON, nullable=True)  # [{"field": "savings_gb", "op": ">", "value": 50}, ...]
    actions_json = Column(JSON, nullable=True)  # [{"type": "queue_top_n", "params": {"n": 20, "preset_id": 1}}, ...]
    last_triggered_at = Column(DateTime, nullable=True)
    trigger_count = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
