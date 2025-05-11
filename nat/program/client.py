import socket

def start_client():
    host = input("IP: ")  # Server's IP address
    port = 65432          # Server's port

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client_socket:
        print(f"Sending message to server at {host}:{port}")

        message = "Hello, Server!"
        client_socket.sendto(message.encode(), (host, port))
        print(f"Sent: {message}")

        data, server_address = client_socket.recvfrom(1024)
        print(f"Received from {server_address}: {data.decode()}")

if __name__ == "__main__":
    start_client()
