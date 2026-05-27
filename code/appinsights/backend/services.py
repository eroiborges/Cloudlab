import random
import time
import logging
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from fastapi import HTTPException
from models import Order, OrderDetail, Product, Customer
from schemas import OrderCreate, OrderResponse
from opentelemetry import trace
from telemetry import tracer, orders_counter, revenue_counter, conversion_counter, error_counter
from config import settings

logger = logging.getLogger(__name__)

class OrderService:
    def __init__(self, db: Session):
        self.db = db
    
    def create_order(self, order_data: OrderCreate) -> OrderResponse:
        """Processa um pedido com diferentes cenários de sucesso/erro"""
        
        with tracer.start_as_current_span("order_processing") as span:
            span.set_attribute("customer_id", order_data.customer_id)
            span.set_attribute("items_count", len(order_data.items))
            
            try:
                # Determina o cenário baseado nas probabilidades configuradas
                scenario = self._determine_scenario()
                span.set_attribute("scenario", scenario)
                
                logger.info(f"Processando pedido para cliente {order_data.customer_id}, cenário: {scenario}")
                
                # Executa o cenário apropriado
                if scenario == "payment_error":
                    return self._simulate_payment_error(order_data)
                elif scenario == "stock_error":
                    return self._simulate_stock_error(order_data)
                else:
                    return self._process_successful_order(order_data)
                    
            except HTTPException:
                # Re-lança HTTPException sem modificar (para erros simulados)
                raise
            except Exception as e:
                logger.error(f"Erro inesperado ao processar pedido: {e}")
                span.record_exception(e)
                span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
                error_counter.add(1, {"error_type": "unexpected", "operation": "order_processing"})
                raise HTTPException(status_code=500, detail="Erro interno do servidor")
    
    def _determine_scenario(self) -> str:
        """Determina qual cenário executar baseado nas probabilidades"""
        rand = random.randint(1, 100)
        
        if rand <= settings.error_payment_rate:
            return "payment_error"
        elif rand <= settings.error_payment_rate + settings.error_stock_rate:
            return "stock_error"
        else:
            return "success"
    
    def _process_successful_order(self, order_data: OrderCreate) -> OrderResponse:
        """Processa um pedido com sucesso"""
        with tracer.start_as_current_span("successful_order_processing"):
            
            # Verifica se o cliente existe
            customer = self.db.query(Customer).filter(Customer.customer_id == order_data.customer_id).first()
            if not customer:
                raise HTTPException(status_code=404, detail="Cliente não encontrado")
            
            # Calcula o total do pedido
            total_amount = 0
            for item in order_data.items:
                product = self.db.query(Product).filter(Product.product_id == item.product_id).first()
                if not product:
                    raise HTTPException(status_code=404, detail=f"Produto {item.product_id} não encontrado")
                
                item_price = item.unit_price if item.unit_price else product.unit_price
                total_amount += item_price * item.quantity * (1 - item.discount)
            
            # Simula tempo de processamento
            time.sleep(random.uniform(0.1, 0.5))
            
            # Cria o pedido
            new_order = Order(
                customer_id=order_data.customer_id,
                order_date=datetime.now(),
                required_date=datetime.now() + timedelta(days=7),
                freight=total_amount * 0.1,  # 10% do valor como frete
                ship_name=order_data.ship_name or customer.company_name,
                ship_address=order_data.ship_address or customer.address,
                ship_city=order_data.ship_city or customer.city,
                ship_region=order_data.ship_region or customer.region,
                ship_postal_code=order_data.ship_postal_code or customer.postal_code,
                ship_country=order_data.ship_country or customer.country
            )
            
            self.db.add(new_order)
            self.db.flush()  # Para obter o order_id
            
            # Adiciona os itens do pedido
            for item in order_data.items:
                product = self.db.query(Product).filter(Product.product_id == item.product_id).first()
                item_price = item.unit_price if item.unit_price else product.unit_price
                
                order_detail = OrderDetail(
                    order_id=new_order.order_id,
                    product_id=item.product_id,
                    unit_price=item_price,
                    quantity=item.quantity,
                    discount=item.discount
                )
                self.db.add(order_detail)
            
            self.db.commit()
            
            # Registra métricas de sucesso
            orders_counter.add(1, {"status": "success", "customer_id": order_data.customer_id})
            revenue_counter.add(total_amount, {"currency": "BRL"})
            conversion_counter.add(1, {"type": "success"})
            
            logger.info(f"Pedido {new_order.order_id} criado com sucesso. Total: R$ {total_amount:.2f}")
            
            return OrderResponse(
                success=True,
                message="Pedido processado com sucesso",
                order_id=new_order.order_id,
                total_amount=total_amount,
                scenario="success"
            )
    
    def _simulate_payment_error(self, order_data: OrderCreate) -> OrderResponse:
        """Simula erro de pagamento (timeout do gateway)"""
        with tracer.start_as_current_span("payment_error_simulation"):
            
            # Simula tempo de processamento reduzido para evitar timeout real
            time.sleep(random.uniform(0.5, 1.0))
            
            error_message = "Timeout do gateway de pagamento - Tente novamente"
            
            # Registra métricas de erro
            error_counter.add(1, {"error_type": "payment_timeout", "operation": "order_processing"})
            conversion_counter.add(1, {"type": "payment_failure"})
            
            logger.error(f"Erro de pagamento simulado para cliente {order_data.customer_id}")
            
            raise HTTPException(
                status_code=503, 
                detail=error_message
            )
    
    def _simulate_stock_error(self, order_data: OrderCreate) -> OrderResponse:
        """Simula erro de validação de estoque"""
        with tracer.start_as_current_span("stock_error_simulation"):
            
            # Seleciona um produto aleatório do pedido para simular falta de estoque
            random_item = random.choice(order_data.items)
            
            # Busca informações do produto para a mensagem
            product = self.db.query(Product).filter(Product.product_id == random_item.product_id).first()
            product_name = product.product_name if product else f"Produto {random_item.product_id}"
            
            # Simula tempo de verificação de estoque
            time.sleep(random.uniform(0.5, 1.5))
            
            error_message = f"Produto '{product_name}' sem estoque suficiente. Disponível: 0, Solicitado: {random_item.quantity}"
            
            # Registra métricas de erro
            error_counter.add(1, {"error_type": "stock_unavailable", "operation": "order_processing"})
            conversion_counter.add(1, {"type": "stock_failure"})
            
            logger.error(f"Erro de estoque simulado para produto {product_name}")
            
            raise HTTPException(
                status_code=409, 
                detail=error_message
            )