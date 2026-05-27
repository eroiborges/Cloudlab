from sqlalchemy import Column, Integer, String, Float, DateTime, Text, ForeignKey
from sqlalchemy.orm import relationship
from database import Base

class Category(Base):
    __tablename__ = "categories"
    
    category_id = Column(Integer, primary_key=True, index=True)
    category_name = Column(String(15), nullable=False)
    description = Column(Text)
    
    products = relationship("Product", back_populates="category")

class Product(Base):
    __tablename__ = "products"
    
    product_id = Column(Integer, primary_key=True, index=True)
    product_name = Column(String(40), nullable=False, index=True)
    supplier_id = Column(Integer, ForeignKey("suppliers.supplier_id"))
    category_id = Column(Integer, ForeignKey("categories.category_id"))
    quantity_per_unit = Column(String(20))
    unit_price = Column(Float, default=0)
    units_in_stock = Column(Integer, default=0)
    units_on_order = Column(Integer, default=0)
    reorder_level = Column(Integer, default=0)
    discontinued = Column(Integer, default=0)
    
    category = relationship("Category", back_populates="products")
    supplier = relationship("Supplier", back_populates="products")

class Supplier(Base):
    __tablename__ = "suppliers"
    
    supplier_id = Column(Integer, primary_key=True, index=True)
    company_name = Column(String(40), nullable=False)
    contact_name = Column(String(30))
    contact_title = Column(String(30))
    address = Column(String(60))
    city = Column(String(15))
    region = Column(String(15))
    postal_code = Column(String(10))
    country = Column(String(15))
    phone = Column(String(24))
    fax = Column(String(24))
    homepage = Column(Text)
    
    products = relationship("Product", back_populates="supplier")

class Customer(Base):
    __tablename__ = "customers"
    
    customer_id = Column(String(5), primary_key=True, index=True)
    company_name = Column(String(40), nullable=False)
    contact_name = Column(String(30))
    contact_title = Column(String(30))
    address = Column(String(60))
    city = Column(String(15))
    region = Column(String(15))
    postal_code = Column(String(10))
    country = Column(String(15))
    phone = Column(String(24))
    fax = Column(String(24))
    
    orders = relationship("Order", back_populates="customer")

class Order(Base):
    __tablename__ = "orders"
    
    order_id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(String(5), ForeignKey("customers.customer_id"))
    employee_id = Column(Integer)
    order_date = Column(DateTime)
    required_date = Column(DateTime)
    shipped_date = Column(DateTime)
    ship_via = Column(Integer)
    freight = Column(Float, default=0)
    ship_name = Column(String(40))
    ship_address = Column(String(60))
    ship_city = Column(String(15))
    ship_region = Column(String(15))
    ship_postal_code = Column(String(10))
    ship_country = Column(String(15))
    
    customer = relationship("Customer", back_populates="orders")
    order_details = relationship("OrderDetail", back_populates="order")

class OrderDetail(Base):
    __tablename__ = "order_details"
    
    order_id = Column(Integer, ForeignKey("orders.order_id"), primary_key=True)
    product_id = Column(Integer, ForeignKey("products.product_id"), primary_key=True)
    unit_price = Column(Float, nullable=False)
    quantity = Column(Integer, nullable=False)
    discount = Column(Float, default=0)
    
    order = relationship("Order", back_populates="order_details")
    product = relationship("Product")