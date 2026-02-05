#!/usr/bin/env python3
"""
Servidor WebSocket em Python usando FastAPI
Demonstração de conexões WebSocket com HTML/JavaScript
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import uvicorn
import json
import asyncio
from datetime import datetime
from typing import List

app = FastAPI(title="WebSocket Test Server", version="1.0.0")

# Lista para gerenciar conexões WebSocket ativas
active_connections: List[WebSocket] = []

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"Nova conexão WebSocket estabelecida. Total: {len(self.active_connections)}")
        
        # Enviar mensagem de boas-vindas
        welcome_msg = {
            "type": "connection",
            "message": "Conectado com sucesso ao WebSocket!",
            "timestamp": datetime.now().strftime("%H:%M:%S"),
            "connection_id": id(websocket)
        }
        await websocket.send_text(json.dumps(welcome_msg))
    
    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
            print(f"Conexão WebSocket encerrada. Total: {len(self.active_connections)}")
    
    async def send_personal_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)
    
    async def broadcast(self, message: str):
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except:
                # Remove conexões inválidas
                self.active_connections.remove(connection)

manager = ConnectionManager()

@app.get("/")
async def get_homepage():
    """Serve a página HTML principal"""
    with open("static/index.html", "r", encoding="utf-8") as f:
        html_content = f.read()
    return HTMLResponse(content=html_content, status_code=200)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Endpoint WebSocket principal"""
    await manager.connect(websocket)
    
    try:
        while True:
            # Receber mensagem do cliente
            data = await websocket.receive_text()
            
            try:
                message_data = json.loads(data)
                print(f"Mensagem recebida: {message_data}")
                
                # Processar diferentes tipos de mensagem
                if message_data.get("type") == "ping":
                    # Responder ao ping
                    pong_response = {
                        "type": "pong",
                        "message": "Pong! Conexão ativa.",
                        "timestamp": datetime.now().strftime("%H:%M:%S"),
                        "original_message": message_data.get("message", "")
                    }
                    await manager.send_personal_message(json.dumps(pong_response), websocket)
                
                elif message_data.get("type") == "echo":
                    # Ecoar mensagem
                    echo_response = {
                        "type": "echo",
                        "message": f"Echo: {message_data.get('message', '')}",
                        "timestamp": datetime.now().strftime("%H:%M:%S")
                    }
                    await manager.send_personal_message(json.dumps(echo_response), websocket)
                
                elif message_data.get("type") == "broadcast":
                    # Broadcast para todas as conexões
                    broadcast_msg = {
                        "type": "broadcast",
                        "message": f"Broadcast: {message_data.get('message', '')}",
                        "timestamp": datetime.now().strftime("%H:%M:%S"),
                        "sender": f"Cliente {id(websocket)}"
                    }
                    await manager.broadcast(json.dumps(broadcast_msg))
                
                else:
                    # Mensagem genérica
                    response = {
                        "type": "message",
                        "message": f"Mensagem recebida: {data}",
                        "timestamp": datetime.now().strftime("%H:%M:%S")
                    }
                    await manager.send_personal_message(json.dumps(response), websocket)
            
            except json.JSONDecodeError:
                # Se não for JSON válido, tratar como texto simples
                response = {
                    "type": "text",
                    "message": f"Texto recebido: {data}",
                    "timestamp": datetime.now().strftime("%H:%M:%S")
                }
                await manager.send_personal_message(json.dumps(response), websocket)
            
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        print("Cliente desconectado")

@app.get("/status")
@app.head("/status")
async def get_status():
    """Endpoint para verificar status do servidor (suporta GET e HEAD)"""
    return {
        "status": "running",
        "active_connections": len(manager.active_connections),
        "timestamp": datetime.now().isoformat()
    }

# Task para enviar mensagens periódicas (opcional)
async def periodic_message():
    """Envia mensagens periódicas para todas as conexões ativas"""
    while True:
        await asyncio.sleep(30)  # A cada 30 segundos
        if manager.active_connections:
            message = {
                "type": "periodic",
                "message": "Mensagem automática - Conexão ainda ativa!",
                "timestamp": datetime.now().strftime("%H:%M:%S"),
                "connections_count": len(manager.active_connections)
            }
            await manager.broadcast(json.dumps(message))

# Configurar arquivos estáticos (CSS, JS, imagens)
app.mount("/static", StaticFiles(directory="static"), name="static")

if __name__ == "__main__":
    import os
    
    # Criar diretório static se não existir
    os.makedirs("static", exist_ok=True)
    
    print("🚀 Iniciando servidor WebSocket...")
    print("📍 Acesse: http://localhost:8000")
    print("🔗 WebSocket: ws://localhost:8000/ws")
    print("ℹ️  Status: http://localhost:8000/status")
    
    # Iniciar task periódica (comentada por padrão)
    # asyncio.create_task(periodic_message())
    
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )