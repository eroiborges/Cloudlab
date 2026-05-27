import { ApplicationInsights } from '@microsoft/applicationinsights-web';
import { ReactPlugin } from '@microsoft/applicationinsights-react-js';

// Configuração do Application Insights - Runtime configuration
const connectionString = window.APPINSIGHTS_CONNECTION_STRING || process.env.REACT_APP_APPINSIGHTS_CONNECTION_STRING || '';

const reactPlugin = new ReactPlugin();

const appInsights = new ApplicationInsights({
  config: {
    connectionString: connectionString,
    extensions: [reactPlugin],
    enableAutoRouteTracking: true,
    enableCorsCorrelation: true,
    enableRequestHeaderTracking: true,
    enableResponseHeaderTracking: true,
    autoTrackPageVisitTime: true,
    enableAjaxPerfTracking: true,
    maxAjaxCallsPerView: 20,
    disableAjaxTracking: false,
    disableFetchTracking: false,
    enableUnhandledPromiseRejectionTracking: true
  }
});

// Inicializa Application Insights se a connection string estiver configurada
if (connectionString) {
  appInsights.loadAppInsights();
  console.log('Application Insights inicializado');
} else {
  console.warn('Application Insights não configurado - Connection string não definida');
}

// Funções utilitárias para telemetria personalizada
export const telemetry = {
  // Rastreia eventos personalizados
  trackEvent: (name, properties = {}, measurements = {}) => {
    try {
      appInsights.trackEvent({ name, properties, measurements });
    } catch (error) {
      console.warn('Erro ao enviar evento para Application Insights:', error);
    }
  },

  // Rastreia métricas customizadas
  trackMetric: (name, average, properties = {}) => {
    try {
      appInsights.trackMetric({ name, average }, properties);
    } catch (error) {
      console.warn('Erro ao enviar métrica para Application Insights:', error);
    }
  },

  // Rastreia exceções
  trackException: (error, properties = {}) => {
    try {
      appInsights.trackException({ exception: error, properties });
    } catch (err) {
      console.warn('Erro ao enviar exceção para Application Insights:', err);
    }
  },

  // Rastreia pageviews personalizados
  trackPageView: (name, url, properties = {}) => {
    try {
      appInsights.trackPageView({ name, uri: url, properties });
    } catch (error) {
      console.warn('Erro ao enviar pageview para Application Insights:', error);
    }
  },

  // Inicia timer para rastreamento de performance
  startTrackPage: (name) => {
    try {
      appInsights.startTrackPage(name);
    } catch (error) {
      console.warn('Erro ao iniciar rastreamento de página:', error);
    }
  },

  // Para timer de performance
  stopTrackPage: (name, properties = {}) => {
    try {
      appInsights.stopTrackPage(name, null, properties);
    } catch (error) {
      console.warn('Erro ao parar rastreamento de página:', error);
    }
  },

  // Flush manual dos dados
  flush: () => {
    try {
      appInsights.flush();
    } catch (error) {
      console.warn('Erro ao fazer flush do Application Insights:', error);
    }
  }
};

// Context para uso no React
export { reactPlugin, appInsights };
export default appInsights;