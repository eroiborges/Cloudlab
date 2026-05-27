import os
import logging
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace, metrics
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from config import settings

logger = logging.getLogger(__name__)

def setup_telemetry(app):
    """Configura OpenTelemetry e Application Insights"""
    try:
        if settings.applicationinsights_connection_string:
            # Configura Azure Monitor
            configure_azure_monitor(
                connection_string=settings.applicationinsights_connection_string,
                enable_live_metrics=True,
                enable_standard_metrics=True
            )
            logger.info("Application Insights configurado com sucesso")
        else:
            logger.warning("Connection string do Application Insights não configurada")
        
        # Instrumenta FastAPI
        FastAPIInstrumentor.instrument_app(app)
        
        # Instrumenta SQLAlchemy
        SQLAlchemyInstrumentor().instrument()
        
        # Instrumenta Psycopg2
        Psycopg2Instrumentor().instrument()
        
        logger.info("Instrumentação OpenTelemetry configurada")
        
    except Exception as e:
        logger.error(f"Erro ao configurar telemetria: {e}")
        # Não falha a aplicação se a telemetria falhar
        pass

def get_tracer():
    """Obtém o tracer OpenTelemetry"""
    return trace.get_tracer(__name__)

def get_meter():
    """Obtém o meter OpenTelemetry"""  
    return metrics.get_meter(__name__)

# Métricas customizadas globais
tracer = get_tracer()
meter = get_meter()

# Contadores de métricas de negócio
orders_counter = meter.create_counter(
    "northwind_orders_total", 
    description="Número total de pedidos processados"
)

revenue_counter = meter.create_counter(
    "northwind_revenue_total", 
    description="Receita total gerada"
)

conversion_counter = meter.create_counter(
    "northwind_conversion_events",
    description="Eventos de conversão (sucesso/falha)"
)

error_counter = meter.create_counter(
    "northwind_errors_total",
    description="Número total de erros por tipo"
)