import os
import logging
from typing import Optional
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Configurações de Banco de Dados
    database_url: str = "postgresql://user:password@localhost:5432/northwind"
    use_managed_identity: bool = False
    
    # Application Insights
    applicationinsights_connection_string: str = ""
    
    # Configurações da API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = False
    
    # Cenários de Erro
    error_payment_rate: int = 15
    error_stock_rate: int = 15
    success_rate: int = 70
    
    class Config:
        env_file = ".env"

settings = Settings()

# Configuração de logging
logging.basicConfig(
    level=logging.INFO if not settings.debug else logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)