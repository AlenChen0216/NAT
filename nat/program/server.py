import socketserver
import argparse
import logging
from datetime import datetime
import http.server
from urllib.parse import parse_qs,urlparse

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class CustomHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Custom handler to log requests and provide test responses"""
    
    def log_message(self, format, *args):
        logging.info(f"{self.client_address[0]}:{self.client_address[1]} - {format%args}")
    
    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        logging.info(f"Query parameters: {query}")

        """Handle GET requests with custom response"""
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        
        # Prepare response content
        response = f"""
        <html>
        <head><title>Network Test Server</title></head>
        <body>
            <h1>Python HTTP Test Server</h1>
            <p>This is a simple HTTP server for network testing.</p>
            <p>Current time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p>Your IP: {self.client_address[0]}</p>
            <p>Your Port: {self.client_address[1]}</p>
            <p>Requested path: {self.path}</p>
            <p>Query parameters: {query['param']}</p>
        </body>
        </html>
        """
        
        self.wfile.write(response.encode('utf-8'))

def run_server(port=8000, bind="0.0.0.0"):
    """Run the HTTP server"""
    handler = CustomHTTPRequestHandler
    
    with socketserver.TCPServer((bind, port), handler) as httpd:
        logging.info(f"Server started at http://{bind}:{port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            logging.info("Server stopped by user")
        finally:
            httpd.server_close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Run a simple HTTP server for network testing')
    parser.add_argument('-p', '--port', type=int, default=8000,
                        help='Port to run the server on (default: 8000)')
    parser.add_argument('-b', '--bind', type=str, default='0.0.0.0',
                        help='Address to bind the server to (default: 0.0.0.0)')
    
    args = parser.parse_args()
    run_server(port=args.port, bind=args.bind)