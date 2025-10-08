import socket
from flask import Flask, request
from flask_restx import Api, Resource
from datetime import datetime, timezone  # Updated for timezone support

app = Flask(__name__)
api = Api(app, version='1.0', title='API for Headers and IP', doc='/swagger/')

API_VERSION = "v1"

@api.route('/health')
class Health(Resource):
    def get(self):
        """
        Health Check Endpoint - GET method
        Used by load balancers to check if the service is healthy
        """
        health_data = {
            "status": "healthy",
            "service": "getheader-backend",
            "version": API_VERSION,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "hostname": socket.gethostname(),
            "uptime_check": "ok"
        }
        return health_data, 200
    
    def head(self):
        """
        Health Check Endpoint - HEAD method
        Used by load balancers for lightweight health checks
        Returns only status code, no body content
        """
        # For HEAD requests, just return empty response with 200 status
        return '', 200

@api.route('/test-params')
class TestParams(Resource):
    def get(self):
        """
        Test Query String Parameters
        Useful for testing load balancer URL rewriting and parameter passing
        Example: /test-params?user=john&env=prod&trace=123
        """
        # Get all query string parameters
        query_params = dict(request.args.items())
        
        # Get the full query string as received
        raw_query_string = request.query_string.decode('utf-8')
        
        # Get URL info for troubleshooting
        url_info = {
            "full_url": request.url,
            "base_url": request.base_url,
            "url_root": request.url_root,
            "path": request.path,
            "raw_query_string": raw_query_string
        }
        
        return {
            "message": "Query string parameters received successfully",
            "query_params": query_params,
            "param_count": len(query_params),
            "url_info": url_info,
            "headers": dict(request.headers),
            "date": datetime.now(timezone.utc).isoformat(),
            "api_version": API_VERSION
        }

@api.route('/headers')
class Headers(Resource):
    def get(self):
        """
        Get HTTP Headers
        """
        return {
            "headers": dict(request.headers),
            "date": datetime.now(timezone.utc).isoformat(),
            "api_version": API_VERSION
        }

@api.route('/getip')
class GetIP(Resource):
    def get(self):
        """
        Get Remote and Local IP
        """
        return {
            "hostname": socket.gethostname(),
            "local_ip": socket.gethostbyname(socket.gethostname()),
            "remote_ip": request.remote_addr,
            "Real_ip": request.environ.get('HTTP_X_REAL_IP', request.remote_addr),
            "xff": request.access_route,
            "date": datetime.now(timezone.utc).isoformat(),
            "api_version": API_VERSION
        }

@api.route('/body')
class Body(Resource):
    def post(self):
        """
        Get Body Content
        """
        return {
            "body": request.get_json(),
            "date": datetime.now(timezone.utc).isoformat(),
            "api_version": API_VERSION
        }

@api.route('/all')
class All(Resource):
    def post(self):
        """
        Get All (Headers, IPs, and Body Content)
        """
        return {
            "headers": dict(request.headers),
            "body": request.get_json(),
            "hostname": socket.gethostname(),
            "local_ip": socket.gethostbyname(socket.gethostname()),
            "remote_ip": request.remote_addr,
            "Real_ip": request.environ.get('HTTP_X_REAL_IP', request.remote_addr),
            "xff": request.access_route,
            "date": datetime.now(timezone.utc).isoformat(),
            "api_version": API_VERSION
        }

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)