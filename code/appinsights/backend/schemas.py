from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class CategoryBase(BaseModel):
    category_name: str
    description: Optional[str] = None

class Category(CategoryBase):
    category_id: int
    
    class Config:
        from_attributes = True

class ProductBase(BaseModel):
    product_name: str
    supplier_id: Optional[int] = None
    category_id: Optional[int] = None
    quantity_per_unit: Optional[str] = None
    unit_price: Optional[float] = 0
    units_in_stock: Optional[int] = 0
    units_on_order: Optional[int] = 0
    reorder_level: Optional[int] = 0
    discontinued: Optional[int] = 0

class Product(ProductBase):
    product_id: int
    category: Optional[Category] = None
    
    class Config:
        from_attributes = True

class CustomerBase(BaseModel):
    customer_id: str
    company_name: str
    contact_name: Optional[str] = None
    contact_title: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    region: Optional[str] = None
    postal_code: Optional[str] = None
    country: Optional[str] = None
    phone: Optional[str] = None
    fax: Optional[str] = None

class Customer(CustomerBase):
    class Config:
        from_attributes = True

class OrderDetailCreate(BaseModel):
    product_id: int
    quantity: int
    unit_price: Optional[float] = None
    discount: Optional[float] = 0

class OrderDetail(OrderDetailCreate):
    order_id: int
    
    class Config:
        from_attributes = True

class OrderCreate(BaseModel):
    customer_id: str
    items: List[OrderDetailCreate]
    ship_name: Optional[str] = None
    ship_address: Optional[str] = None
    ship_city: Optional[str] = None
    ship_region: Optional[str] = None
    ship_postal_code: Optional[str] = None
    ship_country: Optional[str] = None

class Order(BaseModel):
    order_id: int
    customer_id: str
    order_date: Optional[datetime] = None
    required_date: Optional[datetime] = None
    shipped_date: Optional[datetime] = None
    freight: Optional[float] = 0
    ship_name: Optional[str] = None
    ship_address: Optional[str] = None
    ship_city: Optional[str] = None
    ship_region: Optional[str] = None
    ship_postal_code: Optional[str] = None
    ship_country: Optional[str] = None
    order_details: List[OrderDetail] = []
    
    class Config:
        from_attributes = True

class OrderResponse(BaseModel):
    success: bool
    message: str
    order_id: Optional[int] = None
    total_amount: Optional[float] = None
    scenario: Optional[str] = None

class HealthCheck(BaseModel):
    status: str
    timestamp: datetime
    database_status: str
    app_insights_status: str