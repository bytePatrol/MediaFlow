import asyncio
import logging
from datetime import datetime
from typing import Dict, Any, Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.automation_rule import AutomationRule
from app.database import async_session_factory

logger = logging.getLogger(__name__)


class AutomationEngine:
    """Evaluates automation rules when events fire."""

    @staticmethod
    async def fire_event(event_type: str, context: Dict[str, Any]):
        """Called when an event happens. Evaluates all matching enabled rules."""
        async with async_session_factory() as session:
            result = await session.execute(
                select(AutomationRule).where(
                    AutomationRule.trigger_type == event_type,
                    AutomationRule.is_enabled == True,  # noqa: E712
                )
            )
            rules = result.scalars().all()

            for rule in rules:
                try:
                    if AutomationEngine._check_conditions(rule, context):
                        await AutomationEngine._execute_actions(rule, context, session)
                        rule.trigger_count = (rule.trigger_count or 0) + 1
                        rule.last_triggered_at = datetime.utcnow()
                        logger.info(f"Automation rule '{rule.name}' triggered by {event_type}")
                except Exception as e:
                    logger.error(f"Error executing rule '{rule.name}': {e}")

            await session.commit()

    @staticmethod
    def _check_conditions(rule: AutomationRule, context: Dict[str, Any]) -> bool:
        """Check if all conditions in the rule are met."""
        conditions = rule.conditions_json
        if not conditions:
            return True  # No conditions = always match

        for condition in conditions:
            field = condition.get("field", "")
            operator = condition.get("operator", "")
            value = condition.get("value")

            ctx_value = context.get(field)
            if ctx_value is None:
                return False

            if operator == "gt" and not (float(ctx_value) > float(value)):
                return False
            elif operator == "lt" and not (float(ctx_value) < float(value)):
                return False
            elif operator == "gte" and not (float(ctx_value) >= float(value)):
                return False
            elif operator == "lte" and not (float(ctx_value) <= float(value)):
                return False
            elif operator == "eq" and str(ctx_value) != str(value):
                return False
            elif operator == "neq" and str(ctx_value) == str(value):
                return False
            elif operator == "contains" and str(value) not in str(ctx_value):
                return False

        return True

    @staticmethod
    async def _execute_actions(rule: AutomationRule, context: Dict[str, Any], session: AsyncSession):
        """Execute all actions defined in the rule."""
        actions = rule.actions_json
        if not actions:
            return

        for action in actions:
            action_type = action.get("type", "")
            params = action.get("params", {})

            try:
                if action_type == "queue_recommendations":
                    await AutomationEngine._action_queue_recommendations(params, context, session)
                elif action_type == "run_analysis":
                    await AutomationEngine._action_run_analysis(params, context, session)
                elif action_type == "send_notification":
                    await AutomationEngine._action_send_notification(params, context, rule)
                elif action_type == "pause_queue":
                    await AutomationEngine._action_pause_queue(session)
                elif action_type == "deploy_cloud_gpu":
                    await AutomationEngine._action_deploy_cloud_gpu(params, session)
                else:
                    logger.warning(f"Unknown action type: {action_type}")
            except Exception as e:
                logger.error(f"Action '{action_type}' failed: {e}")

    @staticmethod
    async def _action_queue_recommendations(params: Dict, context: Dict, session: AsyncSession):
        """Queue top N recommendations."""
        from app.services.recommendation_service import RecommendationService
        from app.schemas.recommendation import BatchQueueRequest

        limit = int(params.get("limit", 10))
        preset_id = params.get("preset_id")
        min_confidence = float(params.get("min_confidence", 0.5))

        svc = RecommendationService(session)
        recs = await svc.get_recommendations()

        # Filter by confidence and take top N
        eligible = [r for r in recs if (r.confidence or 0) >= min_confidence]
        top_ids = [r.id for r in eligible[:limit]]

        if top_ids:
            req = BatchQueueRequest(recommendation_ids=top_ids, preset_id=preset_id)
            result = await svc.batch_queue(req)
            logger.info(f"Auto-queued {result.get('jobs_created', 0)} jobs")

    @staticmethod
    async def _action_run_analysis(params: Dict, context: Dict, session: AsyncSession):
        """Run intelligence analysis."""
        from app.services.recommendation_service import RecommendationService
        svc = RecommendationService(session)
        library_id = params.get("library_id") or context.get("library_id")
        if library_id:
            await svc.run_library_analysis(int(library_id), trigger="auto")
        else:
            await svc.run_full_analysis(trigger="auto")

    @staticmethod
    async def _action_send_notification(params: Dict, context: Dict, rule: AutomationRule):
        """Send a notification."""
        try:
            from app.utils.notify import fire_notification
            title = params.get("title", f"Automation: {rule.name}")
            body = params.get("body", f"Rule '{rule.name}' triggered")
            await fire_notification("automation.triggered", {
                "title": title,
                "body": body,
                "rule_name": rule.name,
                **context,
            })
        except Exception as e:
            logger.error(f"Notification failed: {e}")

    @staticmethod
    async def _action_pause_queue(session: AsyncSession):
        """Pause the processing queue by setting app setting."""
        from app.models.app_settings import AppSetting
        result = await session.execute(
            select(AppSetting).where(AppSetting.key == "queue.paused")
        )
        setting = result.scalar_one_or_none()
        if setting:
            setting.value = "true"
        else:
            session.add(AppSetting(key="queue.paused", value="true"))

    @staticmethod
    async def _action_deploy_cloud_gpu(params: Dict, session: AsyncSession):
        """Deploy a cloud GPU instance."""
        try:
            from app.services.cloud_provisioning_service import deploy_cloud_gpu
            plan = params.get("plan", "vcg-a16-6c-64g-16vram")
            region = params.get("region", "ewr")
            await deploy_cloud_gpu(plan=plan, region=region)
        except Exception as e:
            logger.error(f"Cloud deploy failed: {e}")
