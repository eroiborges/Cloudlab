import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { telemetry } from '../services/appInsights';
import apiService from '../services/api';

const ProductsPage = () => {
  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState([]);
  const [selectedCategory, setSelectedCategory] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [cart, setCart] = useState([]);
  const productsPerPage = 12;

  useEffect(() => {
    // Rastreia acesso à página de produtos
    telemetry.trackPageView('Products', '/products', {
      section: 'product_catalog',
      purpose: 'product_browsing'
    });
    
    loadCategories();
    loadProducts();
  }, []);

  useEffect(() => {
    loadProducts();
    setCurrentPage(1);
  }, [selectedCategory]);

  const loadCategories = async () => {
    try {
      const categoriesData = await apiService.getCategories();
      setCategories(categoriesData);
      
      telemetry.trackEvent('Categories_Loaded', {
        count: categoriesData.length
      });
    } catch (error) {
      console.error('Erro ao carregar categorias:', error);
      telemetry.trackException(error, {
        type: 'categories_load_error',
        page: 'products'
      });
    }
  };

  const loadProducts = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const skip = (currentPage - 1) * productsPerPage;
      const productsData = await apiService.getProducts(skip, productsPerPage, selectedCategory);
      setProducts(productsData);
      
      telemetry.trackEvent('Products_Loaded', {
        count: productsData.length,
        category: selectedCategory ? selectedCategory.toString() : 'all',
        page: currentPage
      });
      
    } catch (error) {
      console.error('Erro ao carregar produtos:', error);
      setError('Erro ao carregar produtos. Tente novamente.');
      
      telemetry.trackException(error, {
        type: 'products_load_error',
        page: 'products',
        category: selectedCategory
      });
    } finally {
      setLoading(false);
    }
  };

  const handleCategoryChange = (categoryId) => {
    setSelectedCategory(categoryId);
    
    telemetry.trackEvent('Category_Filter_Changed', {
      category_id: categoryId ? categoryId.toString() : 'all',
      timestamp: new Date().toISOString()
    });
  };

  const addToCart = (product) => {
    const existingItem = cart.find(item => item.product_id === product.product_id);
    
    if (existingItem) {
      setCart(cart.map(item =>
        item.product_id === product.product_id
          ? { ...item, quantity: item.quantity + 1 }
          : item
      ));
    } else {
      setCart([...cart, { ...product, quantity: 1 }]);
    }

    // Rastreia adição ao carrinho
    telemetry.trackEvent('Product_Added_To_Cart', {
      product_id: product.product_id.toString(),
      product_name: product.product_name,
      category_id: product.category_id ? product.category_id.toString() : 'unknown',
      unit_price: product.unit_price
    }, {
      cart_size: cart.length + 1
    });

    // Métricas de conversão
    telemetry.trackMetric('Cart_Addition_Rate', 1, {
      product_category: product.category_id ? product.category_id.toString() : 'unknown'
    });
  };

  const removeFromCart = (productId) => {
    const removedItem = cart.find(item => item.product_id === productId);
    setCart(cart.filter(item => item.product_id !== productId));

    if (removedItem) {
      telemetry.trackEvent('Product_Removed_From_Cart', {
        product_id: productId.toString(),
        product_name: removedItem.product_name,
        quantity_removed: removedItem.quantity
      }, {
        cart_size: cart.length - 1
      });
    }
  };

  const getCartItemCount = (productId) => {
    const item = cart.find(item => item.product_id === productId);
    return item ? item.quantity : 0;
  };

  const getTotalCartItems = () => {
    return cart.reduce((total, item) => total + item.quantity, 0);
  };

  const getTotalCartValue = () => {
    return cart.reduce((total, item) => total + (item.unit_price * item.quantity), 0);
  };

  const ProductCard = ({ product }) => {
    const cartQuantity = getCartItemCount(product.product_id);
    
    return (
      <div className="col">
        <div className="card h-100">
          <div className="card-body">
            <h6 className="card-title">{product.product_name}</h6>
            <p className="card-text">
              <small className="text-muted">
                {categories.find(c => c.category_id === product.category_id)?.category_name || 'Sem categoria'}
              </small>
            </p>
            <p className="card-text">
              <strong>R$ {product.unit_price?.toFixed(2) || '0.00'}</strong>
            </p>
            <p className="card-text">
              <small className="text-muted">
                Estoque: {product.units_in_stock || 0} unidades
              </small>
            </p>
          </div>
          <div className="card-footer bg-transparent">
            <div className="d-flex justify-content-between align-items-center">
              <button
                className="btn btn-primary btn-sm"
                onClick={() => addToCart(product)}
                disabled={product.units_in_stock === 0 || product.discontinued === 1}
              >
                <i className="bi bi-cart-plus"></i> 
                {cartQuantity > 0 && <span className="ms-1">({cartQuantity})</span>}
              </button>
              {cartQuantity > 0 && (
                <button
                  className="btn btn-outline-danger btn-sm"
                  onClick={() => removeFromCart(product.product_id)}
                >
                  <i className="bi bi-trash"></i>
                </button>
              )}
              {product.discontinued === 1 && (
                <span className="badge bg-danger">Descontinuado</span>
              )}
            </div>
          </div>
        </div>
      </div>
    );
  };

  if (loading) {
    return (
      <div className="container mt-4">
        <div className="text-center">
          <div className="spinner-border" role="status">
            <span className="visually-hidden">Carregando produtos...</span>
          </div>
          <p className="mt-2">Carregando produtos...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mt-4">
        <div className="alert alert-danger">
          <i className="bi bi-exclamation-triangle"></i> {error}
          <button className="btn btn-outline-danger ms-2" onClick={loadProducts}>
            Tentar Novamente
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="container mt-4">
      {/* Header com carrinho */}
      <div className="row">
        <div className="col-md-8">
          <h2>
            <i className="bi bi-shop"></i> Catálogo de Produtos
          </h2>
          <p className="text-muted">
            Explore os produtos do banco de dados Northwind
          </p>
        </div>
        <div className="col-md-4 text-end">
          <div className="card">
            <div className="card-body">
              <h6>
                <i className="bi bi-cart"></i> Carrinho
              </h6>
              <p className="mb-1">
                <strong>{getTotalCartItems()}</strong> itens
              </p>
              <p className="mb-2">
                <strong>R$ {getTotalCartValue().toFixed(2)}</strong>
              </p>
              <Link 
                to="/demo" 
                className="btn btn-success btn-sm"
                disabled={cart.length === 0}
              >
                <i className="bi bi-credit-card"></i> Finalizar
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Filtros */}
      <div className="row mt-3">
        <div className="col-12">
          <div className="card">
            <div className="card-body">
              <h6>Filtrar por categoria:</h6>
              <div className="d-flex flex-wrap gap-2">
                <button
                  className={`btn btn-sm ${selectedCategory === null ? 'btn-primary' : 'btn-outline-primary'}`}
                  onClick={() => handleCategoryChange(null)}
                >
                  Todas
                </button>
                {categories.map(category => (
                  <button
                    key={category.category_id}
                    className={`btn btn-sm ${selectedCategory === category.category_id ? 'btn-primary' : 'btn-outline-primary'}`}
                    onClick={() => handleCategoryChange(category.category_id)}
                  >
                    {category.category_name}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Grid de produtos */}
      <div className="row mt-4">
        <div className="col-12">
          {products.length === 0 ? (
            <div className="text-center py-5">
              <i className="bi bi-inbox fs-1 text-muted"></i>
              <p className="text-muted mt-2">
                Nenhum produto encontrado para esta categoria.
              </p>
            </div>
          ) : (
            <div className="row row-cols-1 row-cols-md-2 row-cols-lg-3 row-cols-xl-4 g-4">
              {products.map(product => (
                <ProductCard key={product.product_id} product={product} />
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Informações adicionais */}
      <div className="row mt-4">
        <div className="col-12">
          <div className="alert alert-info">
            <i className="bi bi-info-circle"></i>
            <strong> Demonstração:</strong> Este catálogo utiliza dados reais do banco Northwind. 
            Adicione produtos ao carrinho e utilize a página de demo para simular diferentes 
            cenários de compra e monitoramento.
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProductsPage;