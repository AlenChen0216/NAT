import socket

def start_server():
    host = input("IP: ")
    port = 65432

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server_socket:
        server_socket.bind((host, port))
        print(f"Server listening on {host}:{port}")

        while True:
            data, addr = server_socket.recvfrom(1024)
            print(f"Received from {addr}: {data.decode()}")
            server_socket.sendto(data, addr)

if __name__ == "__main__":
    start_server()
