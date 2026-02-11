import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)

websocket_router = APIRouter()


class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.subscriptions: Dict[str, Set[str]] = {}

    async def connect(self, websocket: WebSocket, client_id: str):
        await websocket.accept()
        self.active_connections[client_id] = websocket
        self.subscriptions[client_id] = {"*"}
        logger.info(f"WebSocket client connected: {client_id}")

    def disconnect(self, client_id: str):
        self.active_connections.pop(client_id, None)
        self.subscriptions.pop(client_id, None)
        logger.info(f"WebSocket client disconnected: {client_id}")

    async def broadcast(self, event: str, data: dict):
        message = json.dumps({
            "event": event,
            "timestamp": datetime.utcnow().isoformat(),
            "data": data,
        })
        disconnected = []
        for client_id, ws in list(self.active_connections.items()):
            subs = self.subscriptions.get(client_id, set())
            if "*" in subs or event in subs or event.split(".")[0] + ".*" in subs:
                try:
                    await ws.send_text(message)
                except Exception:
                    disconnected.append(client_id)
        for cid in disconnected:
            self.disconnect(cid)

    async def send_to(self, client_id: str, event: str, data: dict):
        ws = self.active_connections.get(client_id)
        if ws:
            message = json.dumps({
                "event": event,
                "timestamp": datetime.utcnow().isoformat(),
                "data": data,
            })
            try:
                await ws.send_text(message)
            except Exception:
                self.disconnect(client_id)


manager = ConnectionManager()


@websocket_router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    import uuid
    client_id = str(uuid.uuid4())[:8]
    await manager.connect(websocket, client_id)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("action") == "subscribe":
                    events = msg.get("events", [])
                    self_subs = manager.subscriptions.get(client_id, set())
                    self_subs.update(events)
                elif msg.get("action") == "unsubscribe":
                    events = msg.get("events", [])
                    self_subs = manager.subscriptions.get(client_id, set())
                    self_subs -= set(events)
                elif msg.get("action") == "ping":
                    await manager.send_to(client_id, "pong", {})
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        manager.disconnect(client_id)
