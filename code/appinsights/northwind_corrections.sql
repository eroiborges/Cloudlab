-- SCRIPT DE CORREÇÕES PARA NORTHWIND DATABASE
-- Para aplicar no banco existente
-- Execute este script como usuário dbadmin

-- 1. CRIAR SEQUENCES PARA AUTO-INCREMENT (se não existirem)
CREATE SEQUENCE IF NOT EXISTS orders_order_id_seq START WITH 11078;
CREATE SEQUENCE IF NOT EXISTS products_product_id_seq START WITH 78;
CREATE SEQUENCE IF NOT EXISTS categories_category_id_seq START WITH 9;
CREATE SEQUENCE IF NOT EXISTS employees_employee_id_seq START WITH 10;
CREATE SEQUENCE IF NOT EXISTS suppliers_supplier_id_seq START WITH 30;
CREATE SEQUENCE IF NOT EXISTS shippers_shipper_id_seq START WITH 4;

-- 2. ALTERAR TABELAS PARA USAR AS SEQUENCES COMO DEFAULT
ALTER TABLE orders ALTER COLUMN order_id SET DEFAULT nextval('orders_order_id_seq');
ALTER TABLE products ALTER COLUMN product_id SET DEFAULT nextval('products_product_id_seq');
ALTER TABLE categories ALTER COLUMN category_id SET DEFAULT nextval('categories_category_id_seq');
ALTER TABLE employees ALTER COLUMN employee_id SET DEFAULT nextval('employees_employee_id_seq');
ALTER TABLE suppliers ALTER COLUMN supplier_id SET DEFAULT nextval('suppliers_supplier_id_seq');
ALTER TABLE shippers ALTER COLUMN shipper_id SET DEFAULT nextval('shippers_shipper_id_seq');

-- 3. ASSOCIAR SEQUENCES COM AS COLUNAS
ALTER SEQUENCE orders_order_id_seq OWNED BY orders.order_id;
ALTER SEQUENCE products_product_id_seq OWNED BY products.product_id;
ALTER SEQUENCE categories_category_id_seq OWNED BY categories.category_id;
ALTER SEQUENCE employees_employee_id_seq OWNED BY employees.employee_id;
ALTER SEQUENCE suppliers_supplier_id_seq OWNED BY suppliers.supplier_id;
ALTER SEQUENCE shippers_shipper_id_seq OWNED BY shippers.shipper_id;

-- 4. PERMISSÕES PARA O USUÁRIO demouser

-- Permissões em todas as tabelas
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO demouser;

-- Permissões em todas as sequences
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO demouser;

-- Permissões no schema
GRANT USAGE ON SCHEMA public TO demouser;
GRANT CREATE ON SCHEMA public TO demouser;

-- 5. VERIFICAR SE AS PERMISSÕES FORAM APLICADAS
\dp orders
\dp order_details
\dp products
\dp customers
\dp categories

-- 6. TESTAR AS SEQUENCES
SELECT 'orders_order_id_seq next value: ' || nextval('orders_order_id_seq');
SELECT 'products_product_id_seq next value: ' || nextval('products_product_id_seq');

-- 7. RESETAR OS VALORES APÓS TESTE (opcional)
-- SELECT setval('orders_order_id_seq', 11077);
-- SELECT setval('products_product_id_seq', 77);

-- FIM DAS CORREÇÕES
-- Agora a aplicação deve funcionar corretamente com auto-increment e permissões adequadas