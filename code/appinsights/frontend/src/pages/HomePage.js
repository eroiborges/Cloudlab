import React from 'react';
import { Link } from 'react-router-dom';
import { telemetry } from '../services/appInsights';

const HomePage = () => {
  
  React.useEffect(() => {
    // Rastreia acesso à página inicial
    telemetry.trackPageView('Home', '/', {
      section: 'landing_page',
      purpose: 'demo_introduction'
    });
  }, []);

  const handleCardClick = (cardType) => {
    telemetry.trackEvent('Homepage_Card_Click', {
      card_type: cardType,
      timestamp: new Date().toISOString()
    });
  };

  return (
    <div className="container mt-4">
      {/* Hero Section */}
      <div className="row">
        <div className="col-12">
          <div className="jumbotron bg-primary text-white p-5 rounded">
            <div className="text-center">
              <h1 className="display-4">
                <i className="bi bi-shop"></i> Northwind E-commerce
              </h1>
              <p className="lead">
                Demonstração do Azure Application Insights em aplicação 3-tier containerizada
              </p>
              <p>
                Explore cenários de monitoramento APM com PostgreSQL, FastAPI e React
              </p>
              <Link 
                to="/demo" 
                className="btn btn-light btn-lg"
                onClick={() => handleCardClick('hero_demo_button')}
              >
                <i className="bi bi-activity"></i> Iniciar Demo APM
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Features Cards */}
      <div className="row mt-5">
        <div className="col-md-4 mb-4">
          <div className="card h-100 border-primary">
            <div className="card-body text-center">
              <i className="bi bi-graph-up-arrow text-primary fs-1"></i>
              <h5 className="card-title mt-3">Telemetria Completa</h5>
              <p className="card-text">
                Monitore requisições HTTP, exceções, métricas customizadas e 
                performance da aplicação em tempo real.
              </p>
              <Link 
                to="/demo" 
                className="btn btn-outline-primary"
                onClick={() => handleCardClick('telemetry_card')}
              >
                Ver Telemetria
              </Link>
            </div>
          </div>
        </div>

        <div className="col-md-4 mb-4">
          <div className="card h-100 border-success">
            <div className="card-body text-center">
              <i className="bi bi-database text-success fs-1"></i>
              <h5 className="card-title mt-3">Base Northwind</h5>
              <p className="card-text">
                Utilize o clássico banco de dados Northwind com produtos, 
                clientes e pedidos para cenários realistas.
              </p>
              <Link 
                to="/products" 
                className="btn btn-outline-success"
                onClick={() => handleCardClick('products_card')}
              >
                Ver Produtos
              </Link>
            </div>
          </div>
        </div>

        <div className="col-md-4 mb-4">
          <div className="card h-100 border-warning">
            <div className="card-body text-center">
              <i className="bi bi-bug text-warning fs-1"></i>
              <h5 className="card-title mt-3">Simulação de Erros</h5>
              <p className="card-text">
                Simule diferentes cenários de erro para demonstrar capacidades 
                de monitoramento e alertas do APM.
              </p>
              <Link 
                to="/demo" 
                className="btn btn-outline-warning"
                onClick={() => handleCardClick('error_simulation_card')}
              >
                Simular Erros
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Architecture Overview */}
      <div className="row mt-5">
        <div className="col-12">
          <div className="card">
            <div className="card-header bg-light">
              <h5 className="mb-0">
                <i className="bi bi-diagram-3"></i> Arquitetura da Demonstração
              </h5>
            </div>
            <div className="card-body">
              <div className="row">
                <div className="col-md-4">
                  <div className="text-center">
                    <i className="bi bi-browser-chrome text-info fs-2"></i>
                    <h6 className="mt-2">Frontend</h6>
                    <p className="small text-muted">
                      React.js com Bootstrap<br/>
                      Application Insights SDK<br/>
                      Telemetria de usuário
                    </p>
                  </div>
                </div>
                <div className="col-md-4">
                  <div className="text-center">
                    <i className="bi bi-server text-success fs-2"></i>
                    <h6 className="mt-2">Backend</h6>
                    <p className="small text-muted">
                      Python FastAPI<br/>
                      OpenTelemetry + App Insights<br/>
                      Simulação de cenários
                    </p>
                  </div>
                </div>
                <div className="col-md-4">
                  <div className="text-center">
                    <i className="bi bi-database text-primary fs-2"></i>
                    <h6 className="mt-2">Banco de Dados</h6>
                    <p className="small text-muted">
                      PostgreSQL Flexible Server<br/>
                      Managed Identity / Connection String<br/>
                      Schema Northwind
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Monitoring Features */}
      <div className="row mt-4">
        <div className="col-12">
          <div className="card border-info">
            <div className="card-header bg-info text-white">
              <h6 className="mb-0">
                <i className="bi bi-eye"></i> Recursos de Monitoramento Demonstrados
              </h6>
            </div>
            <div className="card-body">
              <div className="row">
                <div className="col-md-6">
                  <ul className="list-unstyled">
                    <li><i className="bi bi-check-circle text-success"></i> Rastreamento de requisições HTTP</li>
                    <li><i className="bi bi-check-circle text-success"></i> Captura automática de exceções</li>
                    <li><i className="bi bi-check-circle text-success"></i> Métricas customizadas de negócio</li>
                    <li><i className="bi bi-check-circle text-success"></i> Telemetria distribuída entre camadas</li>
                  </ul>
                </div>
                <div className="col-md-6">
                  <ul className="list-unstyled">
                    <li><i className="bi bi-check-circle text-success"></i> Monitoramento de performance</li>
                    <li><i className="bi bi-check-circle text-success"></i> Eventos de usuário no frontend</li>
                    <li><i className="bi bi-check-circle text-success"></i> Correlação de logs entre serviços</li>
                    <li><i className="bi bi-check-circle text-success"></i> Dashboards em tempo real</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Call to Action */}
      <div className="row mt-5 mb-5">
        <div className="col-12 text-center">
          <div className="p-4 bg-light rounded">
            <h4>Pronto para explorar?</h4>
            <p className="mb-4">
              Execute diferentes cenários e observe como o Azure Application Insights 
              captura e analisa toda a telemetria da aplicação.
            </p>
            <div className="d-grid gap-2 d-md-flex justify-content-center">
              <Link 
                to="/demo" 
                className="btn btn-primary btn-lg me-2"
                onClick={() => handleCardClick('cta_demo')}
              >
                <i className="bi bi-play-fill"></i> Iniciar Demo
              </Link>
              <Link 
                to="/products" 
                className="btn btn-outline-secondary btn-lg"
                onClick={() => handleCardClick('cta_products')}
              >
                <i className="bi bi-shop"></i> Ver Catálogo
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default HomePage;