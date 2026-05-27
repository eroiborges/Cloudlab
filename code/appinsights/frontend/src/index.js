import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { telemetry } from './services/appInsights';

// Rastreia inicialização da aplicação
telemetry.trackEvent('App_Initialization', {
  timestamp: new Date().toISOString(),
  user_agent: navigator.userAgent,
  url: window.location.href
});

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);