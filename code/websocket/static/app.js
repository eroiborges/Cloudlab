/**
 * WebSocket Client JavaScript
 * Gerencia conexões WebSocket, interface do usuário e mensagens
 */

let socket = null;
let isConnecting = false;
let messageCount = 0;
let connectionStartTime = null;
let connectionTimer = null;

// Elementos DOM
const statusElement = document.getElementById('status');
const connectBtn = document.getElementById('connectBtn');
const disconnectBtn = document.getElementById('disconnectBtn');
const pingBtn = document.getElementById('pingBtn');
const testBtn = document.getElementById('testBtn');
const sendBtn = document.getElementById('sendBtn');
const messagesElement = document.getElementById('messages');
const messageInput = document.getElementById('messageInput');
const messageCountElement = document.getElementById('messageCount');
const connectionTimeElement = document.getElementById('connectionTime');
const pingTimeElement = document.getElementById('pingTime');

/**
 * Atualiza o status da conexão na interface
 */
function updateStatus(status, message) {
    statusElement.className = `status ${status}`;
    statusElement.innerHTML = message;
}

/**
 * Atualiza os botões baseado no estado da conexão
 */
function updateButtons(connected) {
    connectBtn.disabled = connected || isConnecting;
    disconnectBtn.disabled = !connected;
    pingBtn.disabled = !connected;
    testBtn.disabled = !connected;
    sendBtn.disabled = !connected;
    messageInput.disabled = !connected;
}

/**
 * Adiciona mensagem na área de mensagens
 */
function addMessage(content, type = 'system') {
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${type}`;
    
    const timestamp = new Date().toLocaleTimeString();
    messageDiv.innerHTML = `
        <div>${content}</div>
        <div class="timestamp">${timestamp}</div>
    `;
    
    messagesElement.appendChild(messageDiv);
    messagesElement.scrollTop = messagesElement.scrollHeight;
    
    // Atualizar contador
    messageCount++;
    messageCountElement.textContent = messageCount;
}

/**
 * Conectar ao WebSocket
 */
function connectWebSocket() {
    if (socket && socket.readyState === WebSocket.OPEN) {
        addMessage('⚠️ Já conectado!', 'system');
        return;
    }

    isConnecting = true;
    updateStatus('connecting', '⏳ Conectando...');
    updateButtons(false);
    
    try {
        // Usar wss:// se a página for HTTPS, ws:// se for HTTP
        const proto = location.protocol === 'https:' ? 'wss' : 'ws';
        const wsUrl = `${proto}://${window.location.host}/ws`;
        socket = new WebSocket(wsUrl);
        
        socket.onopen = function(event) {
            isConnecting = false;
            connectionStartTime = new Date();
            startConnectionTimer();
            
            updateStatus('connected', '✅ Conectado ao WebSocket!');
            updateButtons(true);
            addMessage('🎉 Conectado com sucesso!', 'system');
            
            console.log('WebSocket conectado:', event);
        };
        
        socket.onmessage = function(event) {
            try {
                const data = JSON.parse(event.data);
                handleMessage(data);
            } catch (error) {
                addMessage(`📨 Mensagem (texto): ${event.data}`, 'received');
            }
        };
        
        socket.onclose = function(event) {
            isConnecting = false;
            stopConnectionTimer();
            
            updateStatus('disconnected', '❌ Desconectado');
            updateButtons(false);
            
            if (event.wasClean) {
                addMessage(`👋 Conexão fechada normalmente (código: ${event.code})`, 'system');
            } else {
                addMessage(`💥 Conexão perdida (código: ${event.code})`, 'error');
            }
            
            console.log('WebSocket fechado:', event);
        };
        
        socket.onerror = function(error) {
            isConnecting = false;
            updateStatus('disconnected', '❌ Erro de conexão');
            updateButtons(false);
            addMessage('🚨 Erro na conexão WebSocket', 'error');
            console.error('Erro WebSocket:', error);
        };
        
    } catch (error) {
        isConnecting = false;
        updateStatus('disconnected', '❌ Erro ao conectar');
        updateButtons(false);
        addMessage(`🚨 Erro: ${error.message}`, 'error');
        console.error('Erro ao criar WebSocket:', error);
    }
}

/**
 * Desconectar do WebSocket
 */
function disconnectWebSocket() {
    if (socket) {
        socket.close(1000, 'Desconexão solicitada pelo usuário');
        socket = null;
    }
}

/**
 * Processar mensagens recebidas
 */
function handleMessage(data) {
    const { type, message, timestamp } = data;
    
    switch (type) {
        case 'connection':
            addMessage(`🔗 ${message}`, 'received');
            break;
        case 'pong':
            const pingTime = Date.now() - pingStartTime;
            pingTimeElement.textContent = pingTime;
            addMessage(`🏓 ${message} (${pingTime}ms)`, 'received');
            break;
        case 'echo':
            addMessage(`📢 ${message}`, 'received');
            break;
        case 'broadcast':
            addMessage(`📡 ${message} [${data.sender}]`, 'received');
            break;
        case 'periodic':
            addMessage(`⏰ ${message}`, 'system');
            break;
        case 'text':
        case 'message':
        default:
            addMessage(`📨 ${message}`, 'received');
            break;
    }
}

/**
 * Enviar mensagem via WebSocket
 */
function sendMessage(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        const messageStr = typeof data === 'string' ? data : JSON.stringify(data);
        socket.send(messageStr);
        
        const displayMessage = typeof data === 'object' ? 
            `${data.type}: ${data.message}` : data;
        addMessage(`📤 Enviado: ${displayMessage}`, 'sent');
        
        return true;
    } else {
        addMessage('⚠️ WebSocket não está conectado!', 'error');
        return false;
    }
}

// Variável para medir ping
let pingStartTime = 0;

/**
 * Enviar ping
 */
function sendPing() {
    pingStartTime = Date.now();
    sendMessage({
        type: 'ping',
        message: 'Teste de ping',
        timestamp: new Date().toISOString()
    });
}

/**
 * Enviar mensagem de teste
 */
function sendTestMessage() {
    sendMessage({
        type: 'echo',
        message: 'Esta é uma mensagem de teste!',
        timestamp: new Date().toISOString()
    });
}

/**
 * Enviar mensagem customizada
 */
function sendCustomMessage() {
    const message = messageInput.value.trim();
    if (!message) {
        addMessage('⚠️ Digite uma mensagem!', 'error');
        return;
    }
    
    sendMessage({
        type: 'broadcast',
        message: message,
        timestamp: new Date().toISOString()
    });
    
    messageInput.value = '';
}

/**
 * Limpar mensagens
 */
function clearMessages() {
    messagesElement.innerHTML = '';
    messageCount = 0;
    messageCountElement.textContent = '0';
}

/**
 * Tratar tecla Enter no input
 */
function handleKeyPress(event) {
    if (event.key === 'Enter') {
        sendCustomMessage();
    }
}

/**
 * Iniciar timer de conexão
 */
function startConnectionTimer() {
    connectionTimer = setInterval(updateConnectionTime, 1000);
}

/**
 * Parar timer de conexão
 */
function stopConnectionTimer() {
    if (connectionTimer) {
        clearInterval(connectionTimer);
        connectionTimer = null;
        connectionTimeElement.textContent = '--';
    }
}

/**
 * Atualizar tempo de conexão
 */
function updateConnectionTime() {
    if (connectionStartTime) {
        const diff = new Date() - connectionStartTime;
        const seconds = Math.floor(diff / 1000);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        
        if (hours > 0) {
            connectionTimeElement.textContent = `${hours}h ${minutes % 60}m`;
        } else if (minutes > 0) {
            connectionTimeElement.textContent = `${minutes}m ${seconds % 60}s`;
        } else {
            connectionTimeElement.textContent = `${seconds}s`;
        }
    }
}

// Inicialização quando a página carrega
document.addEventListener('DOMContentLoaded', function() {
    addMessage('🚀 Página carregada. Clique em "Conectar" para iniciar.', 'system');
    updateButtons(false);
    
    // Auto-conectar (opcional)
    // setTimeout(connectWebSocket, 1000);
});

// Limpar ao sair da página
window.addEventListener('beforeunload', function() {
    if (socket) {
        socket.close();
    }
});