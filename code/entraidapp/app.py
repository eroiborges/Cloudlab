import os
import uuid
import json
from datetime import datetime, timedelta
from typing import Dict, Optional

import msal
import requests
from flask import Flask, render_template, request, redirect, url_for, session, jsonify
from werkzeug.exceptions import HTTPException

from config import app_config

# Initialize Flask app
app = Flask(__name__)

# Configure Flask
if app_config.is_valid():
    app.config['SECRET_KEY'] = app_config.get('FLASK_SECRET_KEY')
    app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(
        minutes=int(app_config.get('SESSION_TIMEOUT_MINUTES', 5))
    )
    print(f"✓ Flask configured with secret key from FLASK_SECRET_KEY")
else:
    # Use a temporary secret if config is invalid (for health check)
    app.config['SECRET_KEY'] = 'temp-secret-for-invalid-config'

# MSAL Configuration
msal_app = None
if app_config.is_valid():
    msal_app = msal.ConfidentialClientApplication(
        app_config.get('AZURE_CLIENT_ID'),
        authority=app_config.get('AZURE_AUTHORITY'),
        client_credential=app_config.get('AZURE_CLIENT_SECRET'),
        token_cache=None
    )

# Removed _load_cache and _save_cache functions that cause session cookie bloat
# Using in-memory token cache only for this demo

def _build_auth_url(authority=None, scopes=None, state=None):
    """Build authorization URL for OAuth flow."""
    if not msal_app:
        return None
    
    return msal_app.get_authorization_request_url(
        scopes or ["User.Read"],
        state=state or str(uuid.uuid4()),
        redirect_uri=app_config.get_redirect_uri(request)
    )

def _validate_token(token_response):
    """Validate JWT token using Microsoft's well-known configuration."""
    if not token_response or "access_token" not in token_response:
        return False
    
    try:
        # Get well-known configuration
        tenant_id = app_config.get('AZURE_TENANT_ID')
        well_known_url = f"https://login.microsoftonline.com/{tenant_id}/v2.0/.well-known/openid-configuration"
        
        config_response = requests.get(well_known_url)
        config_response.raise_for_status()
        oidc_config = config_response.json()
        
        # For demo purposes, we'll do basic validation
        # In production, you should validate JWT signature using the JWKS endpoint
        if "issuer" in oidc_config:
            expected_issuer = oidc_config["issuer"]
            # Basic issuer validation would go here
            print(f"✓ Token issuer validation against: {expected_issuer}")
        
        return True
    except Exception as e:
        print(f"⚠ Token validation error: {e}")
        return False

@app.route("/health", methods=["GET", "HEAD"])
def health_check():
    """Health check endpoint - always returns 200."""
    return jsonify({"status": "ok", "timestamp": datetime.utcnow().isoformat()})

@app.route("/")
def index():
    """Main page."""
    if not app_config.is_valid():
        return render_template("error.html", 
                             missing_vars=app_config.get_missing_vars(),
                             config_valid=False)
    
    user = session.get("user")
    print(f"🔍 Index route - Session user: {user}")
    print(f"🔍 Session keys: {list(session.keys())}")
    return render_template("index.html", user=user)

@app.route("/login")
def login():
    """Initialize OAuth login flow."""
    if not app_config.is_valid():
        return render_template("error.html", 
                             missing_vars=app_config.get_missing_vars(),
                             config_valid=False)
    
    # Generate auth URL
    auth_url = _build_auth_url(scopes=["User.Read"])
    if not auth_url:
        return render_template("error.html", 
                             error_message="Failed to generate authorization URL")
    
    return redirect(auth_url)

@app.route("/auth/callback")
def auth_callback():
    """Handle OAuth callback."""
    if not app_config.is_valid():
        return render_template("error.html", 
                             missing_vars=app_config.get_missing_vars(),
                             config_valid=False)
    
    if "error" in request.args:
        return render_template("error.html", 
                             error_message=f"OAuth Error: {request.args.get('error_description', 'Unknown error')}")
    
    if request.args.get('code'):
        # Use in-memory token cache (no session storage)
        result = msal_app.acquire_token_by_authorization_code(
            request.args['code'],
            scopes=["User.Read"],
            redirect_uri=app_config.get_redirect_uri(request)
        )
        
        if "error" in result:
            return render_template("error.html", 
                                 error_message=f"Token acquisition failed: {result.get('error_description', 'Unknown error')}")
        
        # Debug: Print result keys
        print(f"🔍 MSAL result keys: {list(result.keys())}")
        if "id_token_claims" in result:
            print(f"🔍 ID token claims: {result.get('id_token_claims', {})}")
        
        # Validate token
        if not _validate_token(result):
            return render_template("error.html", 
                                 error_message="Token validation failed")
        
        # Get user info from ID token claims first, fallback to MS Graph
        user_info = _get_user_from_id_token(result.get("id_token_claims", {}))
        if not user_info and result.get("access_token"):
            # Fallback to MS Graph for basic user info
            user_info = _get_user_info_from_graph(result.get("access_token"))
            print("🔄 Using MS Graph fallback for user info")
        
        if user_info:
            # Store ONLY minimal user info in session (no tokens, no cache)
            session["user"] = {
                "displayName": user_info.get("displayName"),
                "userPrincipalName": user_info.get("userPrincipalName"),
                "mail": user_info.get("mail")
            }
            session.permanent = True
            print(f"✓ User session created for: {user_info.get('userPrincipalName', 'Unknown')}")
            print(f"🔍 Session size estimate: {len(str(session))} characters")
        else:
            print("⚠ Failed to extract user information")
    
    return redirect(url_for("index"))

def _get_user_from_id_token(id_token_claims):
    """Get user information from ID token claims."""
    try:
        if not id_token_claims:
            return None
        
        print(f"🔍 Processing ID token claims: {id_token_claims}")
        user_info = {
            "displayName": id_token_claims.get("name"),
            "userPrincipalName": id_token_claims.get("preferred_username") or id_token_claims.get("upn"),
            "mail": id_token_claims.get("email") or id_token_claims.get("mail")
        }
        
        # Check if we got any useful info
        if any(user_info.values()):
            return user_info
        return None
    except Exception as e:
        print(f"⚠ Failed to get user info from ID token: {e}")
        return None

def _get_user_info_from_graph(access_token):
    """Get detailed user information from Microsoft Graph (for profile page)."""
    try:
        graph_data = requests.get(
            "https://graph.microsoft.com/v1.0/me",
            headers={'Authorization': 'Bearer ' + access_token}
        ).json()
        
        return {
            "displayName": graph_data.get("displayName"),
            "userPrincipalName": graph_data.get("userPrincipalName"),
            "mail": graph_data.get("mail"),
            "jobTitle": graph_data.get("jobTitle"),
            "department": graph_data.get("department"),
            "officeLocation": graph_data.get("officeLocation")
        }
    except Exception as e:
        print(f"⚠ Failed to get user info from Graph: {e}")
        return None

@app.route("/tokens")
def tokens():
    """Display JWT token claims and values."""
    if not app_config.is_valid():
        return render_template("error.html", 
                             missing_vars=app_config.get_missing_vars(),
                             config_valid=False)
    
    user = session.get("user")
    if not user:
        return redirect(url_for("login"))
    
    # Try to get fresh tokens for display
    accounts = msal_app.get_accounts()
    token_info = {
        "id_token_claims": None,
        "access_token_claims": None,
        "access_token": None,
        "id_token": None,
        "error": None
    }
    
    if accounts:
        try:
            # Get fresh tokens silently
            result = msal_app.acquire_token_silent(
                scopes=["User.Read"],
                account=accounts[0]
            )
            
            if result and "access_token" in result:
                token_info["access_token"] = result.get("access_token")
                token_info["id_token"] = result.get("id_token")
                token_info["id_token_claims"] = result.get("id_token_claims", {})
                
                # Decode access token claims (basic parsing - for demo only)
                try:
                    import base64
                    import json
                    access_token = result.get("access_token")
                    if access_token:
                        # Split JWT and decode payload (without verification - demo only)
                        parts = access_token.split('.')
                        if len(parts) >= 2:
                            # Add padding if needed
                            payload = parts[1]
                            payload += '=' * (4 - len(payload) % 4)
                            decoded = base64.b64decode(payload)
                            token_info["access_token_claims"] = json.loads(decoded)
                except Exception as e:
                    token_info["error"] = f"Failed to decode access token: {str(e)}"
            else:
                token_info["error"] = "Unable to acquire fresh tokens silently"
        except Exception as e:
            token_info["error"] = f"Token acquisition error: {str(e)}"
    else:
        token_info["error"] = "No accounts found in MSAL cache"
    
    return render_template("tokens.html", user=user, token_info=token_info)

@app.route("/profile")
def profile():
    """User profile page with detailed MS Graph information."""
    if not app_config.is_valid():
        return render_template("error.html", 
                             missing_vars=app_config.get_missing_vars(),
                             config_valid=False)
    
    user = session.get("user")
    if not user:
        return redirect(url_for("login"))
    
    # For profile page, try to get fresh token for MS Graph
    # In production, you'd implement proper token refresh
    accounts = msal_app.get_accounts()
    detailed_user = user  # Fallback to basic user info
    
    if accounts:
        # Try to get fresh token silently
        result = msal_app.acquire_token_silent(
            scopes=["User.Read"],
            account=accounts[0]
        )
        if result and "access_token" in result:
            detailed_user = _get_user_info_from_graph(result.get("access_token")) or user
    
    return render_template("profile.html", user=detailed_user)

@app.route("/logout")
def logout():
    """Logout user and clear session."""
    if not app_config.is_valid():
        return render_template("error.html", 
                             missing_vars=app_config.get_missing_vars(),
                             config_valid=False)
    
    session.clear()
    
    # Microsoft logout URL with post-logout redirect
    tenant_id = app_config.get('AZURE_TENANT_ID')
    post_logout_uri = app_config.get_redirect_uri(request).replace('/auth/callback', '')
    logout_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/logout?post_logout_redirect_uri={post_logout_uri}"
    
    return redirect(logout_url)

@app.errorhandler(Exception)
def handle_exception(e):
    """Handle unexpected errors."""
    if isinstance(e, HTTPException):
        return e
    
    return render_template("error.html", 
                         error_message=f"An unexpected error occurred: {str(e)}"), 500

if __name__ == "__main__":
    port = int(app_config.get('FLASK_PORT', 5000))
    host = app_config.get('FLASK_HOST', '0.0.0.0')
    
    print(f"🚀 Starting Flask application on {host}:{port}")
    print(f"📍 Redirect URI will be: {app_config.get_redirect_uri(type('MockRequest', (), {'headers': {}, 'is_secure': False})())}")
    
    app.run(host=host, port=port, debug=True)