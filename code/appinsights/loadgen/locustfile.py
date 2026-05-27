import os
import random
import time
from typing import List, Dict, Any
from locust import HttpUser, task, between
from faker import Faker

# Configurações do ambiente
TARGET_URL = os.getenv('LOAD_TARGET_URL', 'http://localhost:8000')
SUCCESS_RATE = int(os.getenv('SUCCESS_RATE', '70'))
ERROR_PAYMENT_RATE = int(os.getenv('ERROR_PAYMENT_RATE', '15'))
ERROR_STOCK_RATE = int(os.getenv('ERROR_STOCK_RATE', '15'))

fake = Faker('pt_BR')

class NorthwindEcommerceUser(HttpUser):
    """Usuário simulado que navega e faz compras na aplicação Northwind"""
    
    wait_time = between(1, 3)  # Tempo entre ações
    
    def on_start(self):
        """Inicialização do usuário - carrega dados necessários"""
        self.products = []
        self.categories = []
        self.customers = []
        self.cart = []
        
        # Carrega dados iniciais
        self.load_initial_data()
    
    def load_initial_data(self):
        """Carrega produtos, categorias e clientes disponíveis"""
        try:
            # Carrega categorias
            with self.client.get("/api/categories", catch_response=True, name="load_categories") as response:
                if response.status_code == 200:
                    self.categories = response.json()
                else:
                    response.failure("Failed to load categories")
            
            # Carrega produtos
            with self.client.get("/api/products?limit=50", catch_response=True, name="load_products") as response:
                if response.status_code == 200:
                    self.products = response.json()
                else:
                    response.failure("Failed to load products")
            
            # Carrega alguns clientes
            with self.client.get("/api/customers?limit=10", catch_response=True, name="load_customers") as response:
                if response.status_code == 200:
                    self.customers = response.json()
                else:
                    response.failure("Failed to load customers")
                    
        except Exception as e:
            print(f"Erro ao carregar dados iniciais: {e}")
    
    @task(1)
    def check_health(self):
        """Verifica saúde da aplicação"""
        with self.client.get("/health", catch_response=True, name="health_check") as response:
            if response.status_code != 200:
                response.failure("Health check failed")
    
    @task(5)
    def browse_homepage(self):
        """Navega pela página inicial"""
        with self.client.get("/", catch_response=True, name="homepage") as response:
            if response.status_code != 200:
                response.failure("Homepage failed")
    
    @task(8)
    def browse_categories(self):
        """Navega pelas categorias de produtos"""
        if not self.categories:
            return
            
        category = random.choice(self.categories)
        params = {'category_id': category['categoryid'], 'limit': 20}
        
        with self.client.get("/api/products", params=params, 
                           catch_response=True, name="browse_category") as response:
            if response.status_code == 200:
                products = response.json()
                # Simula tempo de visualização dos produtos
                time.sleep(random.uniform(0.5, 2.0))
            else:
                response.failure("Failed to browse category")
    
    @task(10)
    def browse_products(self):
        """Navega pelos produtos"""
        skip = random.randint(0, 50)
        limit = random.randint(10, 30)
        params = {'skip': skip, 'limit': limit}
        
        with self.client.get("/api/products", params=params, 
                           catch_response=True, name="browse_products") as response:
            if response.status_code == 200:
                # Simula tempo de visualização
                time.sleep(random.uniform(1.0, 3.0))
            else:
                response.failure("Failed to browse products")
    
    @task(6)
    def view_product_details(self):
        """Visualiza detalhes de um produto específico"""
        if not self.products:
            return
            
        product = random.choice(self.products)
        product_id = product['productid']
        
        with self.client.get(f"/api/products/{product_id}", 
                           catch_response=True, name="product_details") as response:
            if response.status_code == 200:
                # Simula tempo de leitura dos detalhes
                time.sleep(random.uniform(2.0, 5.0))
                
                # 30% de chance de adicionar ao carrinho
                if random.random() < 0.3:
                    self.add_to_cart(product)
            else:
                response.failure("Failed to view product details")
    
    def add_to_cart(self, product: Dict[str, Any]):
        """Adiciona produto ao carrinho simulado"""
        # Verifica se o produto já está no carrinho
        existing_item = next((item for item in self.cart if item['productid'] == product['productid']), None)
        
        if existing_item:
            existing_item['quantity'] += 1
        else:
            self.cart.append({
                'productid': product['productid'],
                'productname': product['productname'],
                'unitprice': product['unitprice'],
                'quantity': 1,
                'discount': 0
            })
    
    @task(3)
    def simulate_checkout_success(self):
        """Simula checkout com sucesso"""
        if not self.cart or not self.customers:
            return
        
        customer = random.choice(self.customers)
        
        # Seleciona alguns itens do carrinho
        items_to_buy = random.sample(self.cart, min(len(self.cart), random.randint(1, 3)))
        
        order_data = {
            "customerid": customer['customerid'],
            "items": [
                {
                    "productid": item['productid'],
                    "quantity": item['quantity'],
                    "unitprice": item['unitprice'],
                    "discount": item['discount']
                }
                for item in items_to_buy
            ],
            "shipname": customer.get('companyname', fake.company()),
            "shipaddress": customer.get('address', fake.street_address()),
            "shipcity": customer.get('city', fake.city()),
            "shipcountry": customer.get('country', 'Brazil')
        }
        
        with self.client.post("/api/simulate/success", 
                            catch_response=True, name="checkout_success") as response:
            if response.status_code == 200:
                # Remove itens comprados do carrinho
                for item in items_to_buy:
                    if item in self.cart:
                        self.cart.remove(item)
                
                # Simula tempo de processamento
                time.sleep(random.uniform(1.0, 2.0))
            else:
                response.failure("Checkout success simulation failed")
    
    @task(1)
    def simulate_payment_error(self):
        """Simula erro de pagamento"""
        with self.client.post("/api/simulate/payment-error", 
                            catch_response=True, name="payment_error") as response:
            # Para simulação de erro, esperamos status de erro
            if response.status_code in [503, 500]:
                response.success()
            elif response.status_code == 200:
                # Pode retornar 200 com informação do erro
                response.success()
            else:
                response.failure("Payment error simulation failed")
    
    @task(1)
    def simulate_stock_error(self):
        """Simula erro de estoque"""
        with self.client.post("/api/simulate/stock-error", 
                            catch_response=True, name="stock_error") as response:
            # Para simulação de erro, esperamos status de erro
            if response.status_code in [409, 500]:
                response.success()
            elif response.status_code == 200:
                # Pode retornar 200 com informação do erro
                response.success()
            else:
                response.failure("Stock error simulation failed")
    
    @task(2)
    def realistic_shopping_journey(self):
        """Simula uma jornada completa de compra"""
        if not self.products or not self.customers:
            return
        
        try:
            # 1. Navega por categoria
            if self.categories:
                category = random.choice(self.categories)
                self.client.get(f"/api/products?category_id={category['categoryid']}&limit=10",
                              name="journey_browse_category")
                time.sleep(random.uniform(1.0, 2.0))
            
            # 2. Visualiza alguns produtos
            products_to_view = random.sample(self.products, min(len(self.products), random.randint(2, 5)))
            for product in products_to_view:
                self.client.get(f"/api/products/{product['productid']}", 
                              name="journey_product_view")
                time.sleep(random.uniform(0.5, 1.5))
            
            # 3. Adiciona produtos ao carrinho
            for product in products_to_view[:random.randint(1, 2)]:
                self.add_to_cart(product)
            
            # 4. Simula checkout (70% sucesso, 30% erro)
            if random.random() < 0.7:
                self.simulate_realistic_order()
            else:
                # Simula abandono do carrinho ou erro
                if random.random() < 0.5:
                    self.simulate_payment_error()
                else:
                    self.simulate_stock_error()
                    
        except Exception as e:
            print(f"Erro na jornada de compra: {e}")
    
    def simulate_realistic_order(self):
        """Simula um pedido realista com dados do carrinho"""
        if not self.cart or not self.customers:
            return
        
        customer = random.choice(self.customers)
        
        order_data = {
            "customerid": customer['customerid'],
            "items": [
                {
                    "productid": item['productid'],
                    "quantity": item['quantity'],
                    "unitprice": item['unitprice'],
                    "discount": random.choice([0, 0.05, 0.1])  # Às vezes tem desconto
                }
                for item in self.cart[:random.randint(1, min(len(self.cart), 3))]
            ]
        }
        
        with self.client.post("/api/orders", json=order_data, 
                            catch_response=True, name="realistic_order") as response:
            if response.status_code == 200:
                # Pedido com sucesso - limpa carrinho
                self.cart = []
                time.sleep(random.uniform(0.5, 1.0))
            elif response.status_code in [503, 409]:
                # Erro esperado (pagamento ou estoque)
                response.success()
            else:
                response.failure(f"Order failed with status {response.status_code}")

# Configuração para execução via linha de comando
if __name__ == "__main__":
    import subprocess
    import sys
    
    # Configurações padrão do Locust
    users = os.getenv('LOAD_USERS', '10')
    spawn_rate = os.getenv('LOAD_SPAWN_RATE', '2')
    duration = os.getenv('LOAD_DURATION', '300')
    
    # Executa o Locust
    cmd = [
        sys.executable, '-m', 'locust',
        '-f', __file__,
        '--host', TARGET_URL,
        '--users', str(users),
        '--spawn-rate', str(spawn_rate),
        '--run-time', f'{duration}s',
        '--headless'
    ]
    
    print(f"Iniciando teste de carga com {users} usuários por {duration}s...")
    print(f"Target: {TARGET_URL}")
    
    subprocess.run(cmd)