import requests
import argparse
class Client:
    def __init__(self,url,port):
        self.url = url
        self.port = port
    def get_data(self):
        try:
            response = requests.get(f"{self.url}:{self.port}")
            response.raise_for_status()  # Raise an error for bad responses
            return response.text  # Return the response content
        except requests.exceptions.RequestException as e:
            print(f"Error: {e}")
            return None


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Client for testing network connectivity')
    parser.add_argument('-u', '--url', type=str, default='http://localhost',
                        help='URL to send the request to')
    parser.add_argument('-p', '--port', type=int, default=8000,
                        help='Port to connect to (default: 8000)')
    args = parser.parse_args()
    client = Client(args.url,args.port)
    data = client.get_data()
    if data:
        print("Received data:")
        print(data)
    else:
        print("Failed to retrieve data.")
