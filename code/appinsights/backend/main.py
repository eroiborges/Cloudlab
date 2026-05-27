import logging
import sys
import traceback
from datetime import datetime
from fastapi import FastAPI, Depends, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Optional
from contextlib import asynccontextmanager

from database import get_db, db_connection, Base
from models import Product, Category, Customer, Order
from schemas import (
    Product as ProductSchema, 
    Category as CategorySchema, 
    Customer as CustomerSchema,
    Order as OrderSchema,
    OrderCreate, 
    OrderResponse, 
    HealthCheck
)
from services import OrderService
from telemetry import setup_telemetry, tracer
from config import settings

# Configure logging detalhado
logging.basicConfig(
    level=logging.DEBUG,  # Mudou para DEBUG
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gerencia o ciclo de vida da aplicação"""
    # Startup
    logger.info("Iniciando aplicação Northwind E-commerce")
    
    # Configura telemetria
    setup_telemetry(app)
    
    yield
    
    # Shutdown
    logger.info("Finalizando aplicação")

# Cria a aplicação FastAPI
app = FastAPI(
    title="Northwind E-commerce API",
    description="API de demonstração do Azure Application Insights com banco de dados Northwind",
    version="1.0.0",
    lifespan=lifespan
)

# Middleware de tratamento de exceções global
@app.middleware("http")
async def catch_exceptions_middleware(request: Request, call_next):
    try:
        logger.debug(f"Processing request: {request.method} {request.url}")
        response = await call_next(request)
        logger.debug(f"Response status: {response.status_code}")
        return response
    except Exception as e:
        logger.error(f"Unhandled exception for {request.method} {request.url}: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        return JSONResponse(
            status_code=500,
            content={"detail": f"Internal server error: {str(e)}", "path": str(request.url)}
        )

# Configura CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Em produção, especificar origens específicas
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Endpoints de Health Check
@app.get("/health", response_model=HealthCheck)
async def health_check(db: Session = Depends(get_db)):
    """Endpoint de verificação de saúde da aplicação"""
    with tracer.start_as_current_span("health_check"):
        try:
            # Testa conexão com banco
            db.execute(text("SELECT 1")).fetchone()
            db_status = "healthy"
        except Exception as e:
            logger.error(f"Erro na conexão com banco: {e}")
            db_status = "unhealthy"
        
        # Verifica Application Insights
        app_insights_status = "configured" if settings.applicationinsights_connection_string else "not_configured"
        
        return HealthCheck(
            status="healthy" if db_status == "healthy" else "unhealthy",
            timestamp=datetime.now(),
            database_status=db_status,
            app_insights_status=app_insights_status
        )

@app.get("/")
async def root():
    """Endpoint raiz"""
    return {
        "message": "Northwind E-commerce API - Demo Azure Application Insights",
        "version": "1.0.0",
        "docs": "/docs"
    }

# Endpoints de Produtos
@app.get("/api/products", response_model=List[ProductSchema])
async def get_products(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category_id: Optional[int] = Query(None),
    db: Session = Depends(get_db)
):
    """Lista produtos com paginação e filtro por categoria"""
    with tracer.start_as_current_span("get_products") as span:
        span.set_attribute("skip", skip)
        span.set_attribute("limit", limit)
        
        query = db.query(Product).filter(Product.discontinued == 0)
        
        if category_id:
            query = query.filter(Product.category_id == category_id)
            span.set_attribute("category_id", category_id)
        
        products = query.offset(skip).limit(limit).all()
        
        span.set_attribute("products_count", len(products))
        logger.info(f"Retornando {len(products)} produtos")
        
        return products

@app.get("/api/products/{product_id}", response_model=ProductSchema)
async def get_product(product_id: int, db: Session = Depends(get_db)):
    """Obtém detalhes de um produto específico"""
    with tracer.start_as_current_span("get_product") as span:
        span.set_attribute("product_id", product_id)
        
        product = db.query(Product).filter(Product.product_id == product_id).first()
        
        if not product:
            logger.warning(f"Produto {product_id} não encontrado")
            raise HTTPException(status_code=404, detail="Produto não encontrado")
        
        logger.info(f"Retornando produto {product.product_name}")
        return product

# Endpoints de Categorias
@app.get("/api/categories", response_model=List[CategorySchema])
async def get_categories(db: Session = Depends(get_db)):
    """Lista todas as categorias de produtos"""
    with tracer.start_as_current_span("get_categories"):
        categories = db.query(Category).all()
        
        logger.info(f"Retornando {len(categories)} categorias")
        return categories

@app.get("/api/categories/{category_id}", response_model=CategorySchema)
async def get_category(category_id: int, db: Session = Depends(get_db)):
    """Obtém detalhes de uma categoria específica"""
    with tracer.start_as_current_span("get_category") as span:
        span.set_attribute("category_id", category_id)
        
        category = db.query(Category).filter(Category.category_id == category_id).first()
        
        if not category:
            logger.warning(f"Categoria {category_id} não encontrada")
            raise HTTPException(status_code=404, detail="Categoria não encontrada")
        
        return category

# Endpoints de Clientes
@app.get("/api/customers", response_model=List[CustomerSchema])
async def get_customers(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db)
):
    """Lista clientes com paginação"""
    with tracer.start_as_current_span("get_customers") as span:
        span.set_attribute("skip", skip)
        span.set_attribute("limit", limit)
        
        customers = db.query(Customer).offset(skip).limit(limit).all()
        
        span.set_attribute("customers_count", len(customers))
        return customers

@app.get("/api/customers/{customer_id}", response_model=CustomerSchema)
async def get_customer(customer_id: str, db: Session = Depends(get_db)):
    """Obtém detalhes de um cliente específico"""
    with tracer.start_as_current_span("get_customer") as span:
        span.set_attribute("customer_id", customer_id)
        
        customer = db.query(Customer).filter(Customer.customer_id == customer_id).first()
        
        if not customer:
            logger.warning(f"Cliente {customer_id} não encontrado")
            raise HTTPException(status_code=404, detail="Cliente não encontrado")
        
        return customer

# Endpoints de Pedidos
@app.post("/api/orders", response_model=OrderResponse)
async def create_order(order: OrderCreate, db: Session = Depends(get_db)):
    """Cria um novo pedido - incluindo cenários de erro para demonstração"""
    with tracer.start_as_current_span("create_order") as span:
        span.set_attribute("customer_id", order.customer_id)
        span.set_attribute("items_count", len(order.items))
        
        order_service = OrderService(db)
        return order_service.create_order(order)

@app.get("/api/orders/{order_id}", response_model=OrderSchema)
async def get_order(order_id: int, db: Session = Depends(get_db)):
    """Obtém detalhes de um pedido específico"""
    with tracer.start_as_current_span("get_order") as span:
        span.set_attribute("order_id", order_id)
        
        order = db.query(Order).filter(Order.order_id == order_id).first()
        
        if not order:
            logger.warning(f"Pedido {order_id} não encontrado")
            raise HTTPException(status_code=404, detail="Pedido não encontrado")
        
        return order

# Endpoints de Simulação para Demonstração
@app.post("/api/simulate/success")
async def simulate_success(db: Session = Depends(get_db)):
    """Força um cenário de sucesso para demonstração"""
    with tracer.start_as_current_span("simulate_success"):
        
        # Busca um cliente aleatório
        customer = db.query(Customer).first()
        if not customer:
            raise HTTPException(status_code=404, detail="Nenhum cliente encontrado")
        
        # Busca um produto aleatório
        product = db.query(Product).filter(Product.discontinued == 0).first()
        if not product:
            raise HTTPException(status_code=404, detail="Nenhum produto encontrado")
        
        # Cria um pedido forçando sucesso
        original_success_rate = settings.success_rate
        settings.success_rate = 100
        settings.error_payment_rate = 0
        settings.error_stock_rate = 0
        
        try:
            order_data = OrderCreate(
                customer_id=customer.customer_id,
                items=[{
                    "product_id": product.product_id,
                    "quantity": 1,
                    "unit_price": product.unit_price,
                    "discount": 0
                }]
            )
            
            order_service = OrderService(db)
            result = order_service.create_order(order_data)
            
            return {
                "message": "Cenário de sucesso executado",
                "result": result
            }
            
        finally:
            # Restaura configurações originais
            settings.success_rate = original_success_rate

@app.post("/api/simulate/payment-error")
async def simulate_payment_error(db: Session = Depends(get_db)):
    """Força um erro de pagamento para demonstração"""
    with tracer.start_as_current_span("simulate_payment_error"):
        
        customer = db.query(Customer).first()
        if not customer:
            raise HTTPException(status_code=404, detail="Nenhum cliente encontrado")
        
        product = db.query(Product).filter(Product.discontinued == 0).first()
        if not product:
            raise HTTPException(status_code=404, detail="Nenhum produto encontrado")
        
        # Força erro de pagamento
        settings.error_payment_rate = 100
        settings.error_stock_rate = 0
        settings.success_rate = 0
        
        try:
            order_data = OrderCreate(
                customer_id=customer.customer_id,
                items=[{
                    "product_id": product.product_id,
                    "quantity": 1,
                    "unit_price": product.unit_price,
                    "discount": 0
                }]
            )
            
            order_service = OrderService(db)
            order_service.create_order(order_data)
            
        except HTTPException as e:
            return {
                "message": "Cenário de erro de pagamento executado",
                "error": e.detail,
                "status_code": e.status_code
            }
        finally:
            # Restaura configurações (normalmente não chegaria aqui)
            settings.error_payment_rate = 15

@app.post("/api/simulate/stock-error")
async def simulate_stock_error(db: Session = Depends(get_db)):
    """Força um erro de estoque para demonstração"""
    with tracer.start_as_current_span("simulate_stock_error"):
        
        customer = db.query(Customer).first()
        if not customer:
            raise HTTPException(status_code=404, detail="Nenhum cliente encontrado")
        
        product = db.query(Product).filter(Product.discontinued == 0).first()
        if not product:
            raise HTTPException(status_code=404, detail="Nenhum produto encontrado")
        
        # Força erro de estoque
        settings.error_payment_rate = 0
        settings.error_stock_rate = 100
        settings.success_rate = 0
        
        try:
            order_data = OrderCreate(
                customer_id=customer.customer_id,
                items=[{
                    "product_id": product.product_id,
                    "quantity": 999,  # Quantidade alta para simular falta de estoque
                    "unit_price": product.unit_price,
                    "discount": 0
                }]
            )
            
            order_service = OrderService(db)
            order_service.create_order(order_data)
            
        except HTTPException as e:
            return {
                "message": "Cenário de erro de estoque executado",
                "error": e.detail,
                "status_code": e.status_code
            }
        finally:
            # Restaura configurações (normalmente não chegaria aqui)
            settings.error_stock_rate = 15

# Handler global de exceções
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Handler global para capturar exceções não tratadas"""
    
    # Não intercepta HTTPException - deixa o FastAPI tratar
    if isinstance(exc, HTTPException):
        raise exc
    
    logger.error(f"Exceção não tratada: {exc}")
    
    with tracer.start_as_current_span("unhandled_exception") as span:
        span.record_exception(exc)
        span.set_status(trace.Status(trace.StatusCode.ERROR, str(exc)))
    
    return JSONResponse(
        status_code=500,
        content={
            "message": "Erro interno do servidor",
            "detail": "Entre em contato com o suporte"
        }
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app", 
        host=settings.api_host, 
        port=settings.api_port,
        reload=settings.debug
    )