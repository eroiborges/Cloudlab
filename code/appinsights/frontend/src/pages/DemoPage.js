import React, { useState, useEffect } from 'react';
import { telemetry } from '../services/appInsights';
import apiService from '../services/api';

const DemoPage = () => {
  const [isLoading, setIsLoading] = useState({
    success: false,
    paymentError: false,
    stockError: false
  });
  const [results, setResults] = useState({
    success: null,
    paymentError: null,
    stockError: null
  });
  const [healthStatus, setHealthStatus] = useState(null);

  // Verifica saúde da aplicação ao carregar
  useEffect(() => {
    checkHealth();
    
    // Rastreia acesso à página de demo
    telemetry.trackPageView('Demo APM', '/demo', {
      section: 'application_monitoring_demo',
      purpose: 'error_simulation'
    });
  }, []);

  const checkHealth = async () => {
    try {
      const health = await apiService.healthCheck();
      setHealthStatus(health);
      
      telemetry.trackEvent('Health_Check_Success', {
        database_status: health.database_status,
        app_insights_status: health.app_insights_status
      });
    } catch (error) {
      telemetry.trackException(error, {
        type: 'health_check_error',
        page: 'demo'
      });
    }
  };

  const runScenario = async (scenarioType) => {
    setIsLoading(prev => ({ ...prev, [scenarioType]: true }));
    
    // Rastreia início do cenário
    telemetry.trackEvent('Demo_Scenario_Start', {
      scenario_type: scenarioType,
      timestamp: new Date().toISOString()
    });
    
    try {
      let result;
      const startTime = Date.now();
      
      switch (scenarioType) {
        case 'success':
          result = await apiService.simulateSuccess();
          break;
        case 'paymentError':
          result = await apiService.simulatePaymentError();
          break;
        case 'stockError':
          result = await apiService.simulateStockError();
          break;
        default:
          throw new Error('Cenário não reconhecido');
      }
      
      const duration = Date.now() - startTime;
      
      // Atualiza resultado na UI
      setResults(prev => ({ ...prev, [scenarioType]: result }));
      
      // Rastreia conclusão do cenário
      telemetry.trackEvent('Demo_Scenario_Complete', {
        scenario_type: scenarioType,
        success: result.success || false,
        error_type: result.error?.status_code || 'none',
        timestamp: new Date().toISOString()
      }, {
        duration: duration
      });
      
      // Rastreia métrica de performance do cenário
      telemetry.trackMetric('Demo_Scenario_Duration', duration, {
        scenario: scenarioType,
        success: result.success ? 'true' : 'false'
      });
      
    } catch (error) {
      console.error(`Erro no cenário ${scenarioType}:`, error);
      
      setResults(prev => ({ 
        ...prev, 
        [scenarioType]: { 
          success: false, 
          error: error.message || 'Erro desconhecido' 
        } 
      }));
      
      telemetry.trackException(error, {
        scenario_type: scenarioType,
        type: 'demo_scenario_error',
        page: 'demo'
      });
    } finally {
      setIsLoading(prev => ({ ...prev, [scenarioType]: false }));
    }
  };

  const clearResults = () => {
    setResults({
      success: null,
      paymentError: null,
      stockError: null
    });
    
    telemetry.trackEvent('Demo_Results_Cleared', {
      timestamp: new Date().toISOString()
    });
  };

  const simulateJavaScriptError = () => {
    telemetry.trackEvent('Demo_JS_Error_Triggered', {
      trigger: 'manual',
      timestamp: new Date().toISOString()
    });
    
    // Simula erro JavaScript para demonstração
    try {
      // Força erro acessando propriedade de null
      const nullObject = null;
      console.log(nullObject.property.subProperty);
    } catch (error) {
      telemetry.trackException(error, {
        type: 'simulated_javascript_error',
        trigger: 'demo_button',
        page: 'demo'
      });
      
      alert('Erro JavaScript simulado! Verifique o Application Insights.');
    }
  };

  const ResultCard = ({ title, result, variant }) => {
    if (!result) return null;
    
    return (
      <div className={`alert alert-${result.success ? 'success' : variant} mt-3`}>
        <h6 className="alert-heading">
          <i className={`bi bi-${result.success ? 'check-circle' : 'exclamation-triangle'}`}></i>
          {' '}{title}
        </h6>
        {result.success ? (
          <div>
            <p className="mb-1">{result.message}</p>
            {result.result && (
              <small className="text-muted">
                Pedido ID: {result.result.order_id} | 
                Total: R$ {result.result.total_amount?.toFixed(2)}
              </small>
            )}
          </div>
        ) : (
          <div>
            <p className="mb-1">Erro capturado:</p>
            <code className="small">
              {result.error?.detail || result.error || 'Erro desconhecido'}
            </code>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="container mt-4">
      <div className="row">
        <div className="col-md-8">
          <div className="card">
            <div className="card-header bg-primary text-white">
              <h4 className="mb-0">
                <i className="bi bi-activity"></i> Demo de Monitoramento APM
              </h4>
              <small>Simulação de cenários para demonstração do Azure Application Insights</small>
            </div>
            
            <div className="card-body">
              <div className="row g-3">
                
                {/* Cenário de Sucesso */}
                <div className="col-md-6">
                  <div className="card border-success">
                    <div className="card-body text-center">
                      <i className="bi bi-check-circle-fill text-success fs-2"></i>
                      <h5 className="card-title mt-2">Fluxo de Sucesso</h5>
                      <p className="card-text small">
                        Simula um pedido processado com sucesso, 
                        gerando métricas de receita e conversão.
                      </p>
                      <button
                        className="btn btn-success"
                        onClick={() => runScenario('success')}
                        disabled={isLoading.success}
                      >
                        {isLoading.success ? (
                          <>
                            <span className="spinner-border spinner-border-sm me-2"></span>
                            Processando...
                          </>
                        ) : (
                          <>
                            <i className="bi bi-play-fill"></i> Executar
                          </>
                        )}
                      </button>
                    </div>
                  </div>
                </div>

                {/* Erro de Pagamento */}
                <div className="col-md-6">
                  <div className="card border-warning">
                    <div className="card-body text-center">
                      <i className="bi bi-credit-card-fill text-warning fs-2"></i>
                      <h5 className="card-title mt-2">Erro de Pagamento</h5>
                      <p className="card-text small">
                        Simula timeout do gateway de pagamento,
                        demonstrando captura de erros de serviços externos.
                      </p>
                      <button
                        className="btn btn-warning"
                        onClick={() => runScenario('paymentError')}
                        disabled={isLoading.paymentError}
                      >
                        {isLoading.paymentError ? (
                          <>
                            <span className="spinner-border spinner-border-sm me-2"></span>
                            Processando...
                          </>
                        ) : (
                          <>
                            <i className="bi bi-play-fill"></i> Executar
                          </>
                        )}
                      </button>
                    </div>
                  </div>
                </div>

                {/* Erro de Estoque */}
                <div className="col-md-6">
                  <div className="card border-danger">
                    <div className="card-body text-center">
                      <i className="bi bi-box-seam text-danger fs-2"></i>
                      <h5 className="card-title mt-2">Erro de Estoque</h5>
                      <p className="card-text small">
                        Simula produto sem estoque suficiente,
                        demonstrando validação de regras de negócio.
                      </p>
                      <button
                        className="btn btn-danger"
                        onClick={() => runScenario('stockError')}
                        disabled={isLoading.stockError}
                      >
                        {isLoading.stockError ? (
                          <>
                            <span className="spinner-border spinner-border-sm me-2"></span>
                            Processando...
                          </>
                        ) : (
                          <>
                            <i className="bi bi-play-fill"></i> Executar
                          </>
                        )}
                      </button>
                    </div>
                  </div>
                </div>

                {/* Erro Frontend */}
                <div className="col-md-6">
                  <div className="card border-info">
                    <div className="card-body text-center">
                      <i className="bi bi-bug-fill text-info fs-2"></i>
                      <h5 className="card-title mt-2">Erro JavaScript</h5>
                      <p className="card-text small">
                        Simula erro no frontend,
                        demonstrando captura de exceções JavaScript.
                      </p>
                      <button
                        className="btn btn-info"
                        onClick={simulateJavaScriptError}
                      >
                        <i className="bi bi-play-fill"></i> Executar
                      </button>
                    </div>
                  </div>
                </div>

              </div>

              {/* Botão de Limpar */}
              <div className="text-center mt-4">
                <button
                  className="btn btn-outline-secondary"
                  onClick={clearResults}
                  disabled={!Object.values(results).some(r => r !== null)}
                >
                  <i className="bi bi-arrow-clockwise"></i> Limpar Resultados
                </button>
              </div>

              {/* Resultados */}
              <ResultCard 
                title="Resultado do Fluxo de Sucesso" 
                result={results.success} 
                variant="success" 
              />
              <ResultCard 
                title="Resultado do Erro de Pagamento" 
                result={results.paymentError} 
                variant="warning" 
              />
              <ResultCard 
                title="Resultado do Erro de Estoque" 
                result={results.stockError} 
                variant="danger" 
              />
            </div>
          </div>
        </div>

        {/* Sidebar com Status */}
        <div className="col-md-4">
          <div className="card">
            <div className="card-header">
              <h5 className="mb-0">
                <i className="bi bi-heartbeat"></i> Status da Aplicação
              </h5>
            </div>
            <div className="card-body">
              {healthStatus ? (
                <div>
                  <div className="d-flex justify-content-between align-items-center mb-2">
                    <span>Status Geral:</span>
                    <span className={`badge bg-${healthStatus.status === 'healthy' ? 'success' : 'danger'}`}>
                      {healthStatus.status === 'healthy' ? 'Saudável' : 'Não Saudável'}
                    </span>
                  </div>
                  <div className="d-flex justify-content-between align-items-center mb-2">
                    <span>Banco de Dados:</span>
                    <span className={`badge bg-${healthStatus.database_status === 'healthy' ? 'success' : 'danger'}`}>
                      {healthStatus.database_status === 'healthy' ? 'OK' : 'Erro'}
                    </span>
                  </div>
                  <div className="d-flex justify-content-between align-items-center mb-2">
                    <span>App Insights:</span>
                    <span className={`badge bg-${healthStatus.app_insights_status === 'configured' ? 'success' : 'warning'}`}>
                      {healthStatus.app_insights_status === 'configured' ? 'Configurado' : 'Não Configurado'}
                    </span>
                  </div>
                  <small className="text-muted">
                    Última verificação: {new Date(healthStatus.timestamp).toLocaleTimeString('pt-BR')}
                  </small>
                </div>
              ) : (
                <div className="text-center">
                  <div className="spinner-border text-primary" role="status">
                    <span className="visually-hidden">Carregando...</span>
                  </div>
                  <p className="mt-2 small text-muted">Verificando status...</p>
                </div>
              )}
              
              <hr />
              
              <button 
                className="btn btn-outline-primary btn-sm w-100" 
                onClick={checkHealth}
              >
                <i className="bi bi-arrow-clockwise"></i> Atualizar Status
              </button>
            </div>
          </div>

          {/* Informações sobre Monitoramento */}
          <div className="card mt-3">
            <div className="card-header">
              <h6 className="mb-0">
                <i className="bi bi-info-circle"></i> Sobre o Monitoramento
              </h6>
            </div>
            <div className="card-body">
              <p className="small">
                Esta demo demonstra como o Azure Application Insights captura:
              </p>
              <ul className="small">
                <li>Telemetria de requisições HTTP</li>
                <li>Exceções e erros da aplicação</li>
                <li>Métricas customizadas de negócio</li>
                <li>Performance e dependências</li>
                <li>Eventos de usuário no frontend</li>
              </ul>
              <p className="small text-muted mt-2">
                Cada cenário gera diferentes tipos de telemetria para análise no Azure Portal.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default DemoPage;