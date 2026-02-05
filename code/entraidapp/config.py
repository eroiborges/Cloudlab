import os
from typing import Dict, List, Optional

class Config:
    """Application configuration with environment validation."""
    
    # Required environment variables
    REQUIRED_VARS = {
        'AZURE_TENANT_ID': 'Azure AD Tenant ID',
        'AZURE_CLIENT_ID': 'Azure AD Application (Client) ID', 
        'AZURE_CLIENT_SECRET': 'Azure AD Client Secret',
        'AZURE_AUTHORITY': 'Azure AD Authority URL',
        'FLASK_SECRET_KEY': 'Flask Session Secret Key',
        'FLASK_HOST': 'Flask Host Address',
        'FLASK_PORT': 'Flask Port Number'
    }
    
    # Optional environment variables with defaults
    OPTIONAL_VARS = {
        'APP_ENVIRONMENT': 'dev',
        'CUSTOM_FQDN': 'api.eroicloud.com.br',
        'SESSION_TIMEOUT_MINUTES': '5',
        'AZURE_CUSTOM_SCOPES': 'api://de741bd5-db77-4bb9-97ef-203ed8b0daa3/appcheck'
    }
    
    def __init__(self):
        """Initialize configuration and validate environment variables."""
        self.config_valid = True
        self.missing_vars = []
        self.config = {}
        
        # Load and validate required variables
        for var_name, description in self.REQUIRED_VARS.items():
            value = os.environ.get(var_name)
            if not value:
                self.config_valid = False
                self.missing_vars.append({
                    'name': var_name,
                    'description': description,
                    'required': True
                })
            else:
                self.config[var_name] = value
        
        # Load optional variables with defaults
        for var_name, default_value in self.OPTIONAL_VARS.items():
            self.config[var_name] = os.environ.get(var_name, default_value)
        
        # Print configuration status
        self._print_config_status()
    
    def _print_config_status(self):
        """Print configuration validation results to stdout."""
        if self.config_valid:
            print("✓ Configuration validation successful")
            print(f"✓ Environment: {self.config.get('APP_ENVIRONMENT')}")
            print(f"✓ Host: {self.config.get('FLASK_HOST')}:{self.config.get('FLASK_PORT')}")
        else:
            print("⚠ Configuration validation failed - missing environment variables:")
            for var in self.missing_vars:
                print(f"  - {var['name']}: {var['description']}")
            print("\nApplication will start but authentication features will be disabled.")
            print("Set missing variables and restart the application.")
    
    def get(self, key: str, default=None):
        """Get configuration value."""
        return self.config.get(key, default)
    
    def is_valid(self) -> bool:
        """Check if configuration is valid."""
        return self.config_valid
    
    def get_missing_vars(self) -> List[Dict]:
        """Get list of missing variables."""
        return self.missing_vars
    
    def get_redirect_uri(self, request) -> str:
        """Generate redirect URI based on request and environment."""
        # Determine protocol
        if request.headers.get('X-Forwarded-Proto') == 'https':
            protocol = 'https'
        elif request.headers.get('X-Forwarded-Proto') == 'http':
            protocol = 'http'
        else:
            protocol = 'https' if request.is_secure else 'http'
        
        # Determine host
        if self.config.get('APP_ENVIRONMENT') == 'dev':
            host = f"localhost:{self.config.get('FLASK_PORT')}"
        else:
            host = self.config.get('CUSTOM_FQDN')
        
        return f"{protocol}://{host}/auth/callback"
    
    def get_custom_scopes(self) -> List[str]:
        """Get custom API scopes as a list."""
        scopes_str = self.config.get('AZURE_CUSTOM_SCOPES', '')
        if not scopes_str:
            return []
        # Support multiple scopes separated by spaces
        return [scope.strip() for scope in scopes_str.split() if scope.strip()]

# Global configuration instance
app_config = Config()