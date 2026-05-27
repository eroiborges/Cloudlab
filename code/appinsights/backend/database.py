import os
import logging
from sqlalchemy import create_engine, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from azure.identity import DefaultAzureCredential
from config import settings

logger = logging.getLogger(__name__)

Base = declarative_base()

class DatabaseConnection:
    def __init__(self):
        self.engine = None
        self.SessionLocal = None
        self._setup_connection()
    
    def _setup_connection(self):
        """Configura a conexão com PostgreSQL usando Managed Identity ou connection string"""
        try:
            if settings.use_managed_identity:
                logger.info("Configurando conexão com Managed Identity")
                self._setup_managed_identity_connection()
            else:
                logger.info("Configurando conexão com connection string")
                self._setup_connection_string()
                
            # Testa a conexão
            self._test_connection()
            
        except Exception as e:
            logger.error(f"Erro ao configurar conexão com banco de dados: {e}")
            raise
    
    def _setup_managed_identity_connection(self):
        """Configura conexão usando System Managed Identity"""
        try:
            credential = DefaultAzureCredential()
            
            # Extrai informações da DATABASE_URL
            db_url = settings.database_url.replace("postgresql://", "")
            if "@" in db_url:
                _, server_part = db_url.split("@", 1)
            else:
                server_part = db_url
            
            server_db = server_part.split("/")
            server_port = server_db[0].split(":")
            server = server_port[0]
            port = server_port[1] if len(server_port) > 1 else "5432"
            database = server_db[1] if len(server_db) > 1 else "northwind"
            
            # Obtém o token de acesso
            token_response = credential.get_token("https://ossrdbms-aad.database.windows.net/.default")
            access_token = token_response.token
            
            # Monta a connection string com o token
            connection_string = f"postgresql://{server}:{port}/{database}?sslmode=require"
            
            self.engine = create_engine(
                connection_string,
                connect_args={"password": access_token},
                echo=settings.debug
            )
            
        except Exception as e:
            logger.error(f"Erro ao configurar Managed Identity: {e}")
            raise
    
    def _setup_connection_string(self):
        """Configura conexão usando connection string tradicional"""
        self.engine = create_engine(
            settings.database_url,
            echo=settings.debug
        )
    
    def _test_connection(self):
        """Testa a conexão com o banco de dados"""
        try:
            with self.engine.connect() as connection:
                result = connection.execute(text("SELECT 1"))
                logger.info("Conexão com banco de dados estabelecida com sucesso")
        except Exception as e:
            logger.error(f"Falha no teste de conexão: {e}")
            raise
    
    def get_session_local(self):
        """Retorna a classe de sessão configurada"""
        if self.SessionLocal is None:
            self.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)
        return self.SessionLocal

# Instância global da conexão
db_connection = DatabaseConnection()
SessionLocal = db_connection.get_session_local()

def get_db():
    """Dependency para FastAPI obter sessão do banco"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()