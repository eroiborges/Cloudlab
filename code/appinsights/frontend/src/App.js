import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { AppInsightsContext } from '@microsoft/applicationinsights-react-js';
import { reactPlugin } from './services/appInsights';

// Bootstrap CSS
import 'bootstrap/dist/css/bootstrap.min.css';

// Bootstrap Icons
import 'bootstrap-icons/font/bootstrap-icons.css';

// Componentes
import Header from './components/Header';
import HomePage from './pages/HomePage';
import ProductsPage from './pages/ProductsPage';
import DemoPage from './pages/DemoPage';

// Estilos customizados
import './App.css';

function App() {
  return (
    <AppInsightsContext.Provider value={reactPlugin}>
      <Router>
        <div className="App">
          <Header />
          <main className="flex-grow-1">
            <Routes>
              <Route path="/" element={<HomePage />} />
              <Route path="/products" element={<ProductsPage />} />
              <Route path="/demo" element={<DemoPage />} />
            </Routes>
          </main>
          
          {/* Footer */}
          <footer className="bg-light mt-5 py-4">
            <div className="container">
              <div className="row">
                <div className="col-md-6">
                  <h6>Northwind E-commerce Demo</h6>
                  <p className="text-muted small">
                    Demonstração do Azure Application Insights com aplicação 3-tier containerizada.
                  </p>
                </div>
                <div className="col-md-6 text-md-end">
                  <p className="text-muted small">
                    <i className="bi bi-cloud-check"></i> Powered by Azure
                    <br />
                    <i className="bi bi-activity"></i> Monitorado por Application Insights
                  </p>
                </div>
              </div>
            </div>
          </footer>
        </div>
      </Router>
    </AppInsightsContext.Provider>
  );
}

export default App;