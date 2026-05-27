import axios from 'axios';
import { telemetry } from './appInsights';

// Configuração base da API - Runtime configuration
const API_BASE_URL = window.API_BASE_URL || process.env.REACT_APP_API_BASE_URL || 'http://localhost:8000';

// Instância do Axios configurada
const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Interceptor para requisições - adiciona telemetria
api.interceptors.request.use(
  (config) => {
    // Rastreia início da requisição
    const startTime = Date.now();
    config.metadata = { startTime };
    
    telemetry.trackEvent('API_Request_Start', {
      url: config.url,
      method: config.method?.toUpperCase(),
      baseURL: config.baseURL
    });
    
    return config;
  },
  (error) => {
    telemetry.trackException(error, {
      type: 'request_interceptor_error',
      message: error.message
    });
    return Promise.reject(error);
  }
);

// Interceptor para respostas - adiciona telemetria
api.interceptors.response.use(
  (response) => {
    // Calcula tempo de resposta
    const endTime = Date.now();
    const duration = endTime - (response.config.metadata?.startTime || endTime);
    
    // Rastreia sucesso da requisição
    telemetry.trackEvent('API_Request_Success', {
      url: response.config.url,
      method: response.config.method?.toUpperCase(),
      status: response.status.toString(),
      baseURL: response.config.baseURL
    }, {
      duration: duration,
      responseSize: JSON.stringify(response.data).length
    });
    
    // Rastreia métrica de performance
    telemetry.trackMetric('API_Response_Time', duration, {
      endpoint: response.config.url,
      method: response.config.method?.toUpperCase()
    });
    
    return response;
  },
  (error) => {
    // Calcula tempo até o erro
    const endTime = Date.now();
    const duration = endTime - (error.config?.metadata?.startTime || endTime);
    
    // Propriedades do erro
    const errorProps = {
      url: error.config?.url,
      method: error.config?.method?.toUpperCase(),
      baseURL: error.config?.baseURL,
      errorCode: error.code,
      errorMessage: error.message
    };
    
    if (error.response) {
      // Erro de resposta do servidor
      errorProps.status = error.response.status.toString();
      errorProps.statusText = error.response.statusText;
      errorProps.responseData = JSON.stringify(error.response.data);
      
      telemetry.trackEvent('API_Request_Error', errorProps, {
        duration: duration
      });
    } else {
      // Erro de rede ou timeout
      telemetry.trackEvent('API_Network_Error', errorProps, {
        duration: duration
      });
    }
    
    // Rastreia exceção
    telemetry.trackException(error, {
      type: 'api_error',
      ...errorProps
    });
    
    return Promise.reject(error);
  }
);

// Serviços da API
export const apiService = {
  
  // Health Check
  async healthCheck() {
    const response = await api.get('/health');
    return response.data;
  },

  // Produtos
  async getProducts(skip = 0, limit = 100, categoryId = null) {
    const params = { skip, limit };
    if (categoryId) params.category_id = categoryId;
    
    const response = await api.get('/api/products', { params });
    return response.data;
  },

  async getProduct(productId) {
    const response = await api.get(`/api/products/${productId}`);
    return response.data;
  },

  // Categorias
  async getCategories() {
    const response = await api.get('/api/categories');
    return response.data;
  },

  async getCategory(categoryId) {
    const response = await api.get(`/api/categories/${categoryId}`);
    return response.data;
  },

  // Clientes
  async getCustomers(skip = 0, limit = 50) {
    const response = await api.get('/api/customers', {
      params: { skip, limit }
    });
    return response.data;
  },

  async getCustomer(customerId) {
    const response = await api.get(`/api/customers/${customerId}`);
    return response.data;
  },

  // Pedidos
  async createOrder(orderData) {
    const response = await api.post('/api/orders', orderData);
    return response.data;
  },

  async getOrder(orderId) {
    const response = await api.get(`/api/orders/${orderId}`);
    return response.data;
  },

  // Simulações para demonstração
  async simulateSuccess() {
    try {
      const response = await api.post('/api/simulate/success');
      const data = response.data;
      // Retorna no formato esperado pelo ResultCard
      return {
        success: data.result?.success || true,
        message: data.message,
        result: data.result
      };
    } catch (error) {
      // Para simulações, pode retornar erro como parte do fluxo normal
      return {
        success: false,
        error: error.response?.data || error.message
      };
    }
  },

  async simulatePaymentError() {
    try {
      const response = await api.post('/api/simulate/payment-error');
      const data = response.data;
      // Retorna no formato esperado pelo ResultCard
      return {
        success: false, // Este sempre será um erro simulado
        message: data.message,
        error: data.error || data
      };
    } catch (error) {
      return {
        success: false,
        error: error.response?.data || error.message
      };
    }
  },

  async simulateStockError() {
    try {
      const response = await api.post('/api/simulate/stock-error');
      const data = response.data;
      // Retorna no formato esperado pelo ResultCard
      return {
        success: false, // Este sempre será um erro simulado
        message: data.message,
        error: data.error || data
      };
    } catch (error) {
      return {
        success: false,
        error: error.response?.data || error.message
      };
    }
  }
};

export default apiService;