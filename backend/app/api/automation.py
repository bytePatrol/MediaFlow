from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete
from typing import List

from app.database import get_session
from app.models.automation_rule import AutomationRule
from app.schemas.automation import AutomationRuleCreate, AutomationRuleUpdate, AutomationRuleResponse

router = APIRouter()


@router.get("/", response_model=List[AutomationRuleResponse])
async def list_rules(session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        select(AutomationRule).order_by(AutomationRule.created_at.desc())
    )
    return result.scalars().all()


@router.post("/", response_model=AutomationRuleResponse)
async def create_rule(request: AutomationRuleCreate, session: AsyncSession = Depends(get_session)):
    rule = AutomationRule(
        name=request.name,
        trigger_type=request.trigger_type,
        conditions_json=request.conditions_json,
        actions_json=request.actions_json,
        is_enabled=request.is_enabled,
    )
    session.add(rule)
    await session.commit()
    await session.refresh(rule)
    return rule


@router.put("/{rule_id}", response_model=AutomationRuleResponse)
async def update_rule(rule_id: int, request: AutomationRuleUpdate, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(AutomationRule).where(AutomationRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Rule not found")
    for field, value in request.model_dump(exclude_unset=True).items():
        setattr(rule, field, value)
    await session.commit()
    await session.refresh(rule)
    return rule


@router.delete("/{rule_id}")
async def delete_rule(rule_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(AutomationRule).where(AutomationRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Rule not found")
    await session.delete(rule)
    await session.commit()
    return {"status": "deleted"}


@router.post("/{rule_id}/toggle", response_model=AutomationRuleResponse)
async def toggle_rule(rule_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(AutomationRule).where(AutomationRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Rule not found")
    rule.is_enabled = not rule.is_enabled
    await session.commit()
    await session.refresh(rule)
    return rule
