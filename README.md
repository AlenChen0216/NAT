
[comment]: # (SPDX-License-Identifier:  Apache-2.0)

# Simple NAT Implementation Using P4_16

## 目錄

1. [**功能簡介**](#1功能簡介)
2. [**系統環境**](#2環境介紹)
3. [**運行方式**](#3運行方式)
4. [**重點技術**](#4重點技術)
5. **成果**
6. **遇到的問題**

## 1.功能簡介

### 功能

本專案使用P4程式語言實做NAT(Network Address Translation)，網路位址轉譯功能。

專案中只使用P4語言設計Switch的data plane pipeline流程，使原先未支援NAT功能之Switch也能實現IP轉譯功能。本專案主要利用到P4中的register功能來紀錄**對外的Port號**與對應的**內網使用者之Port號與IP**，使Switch在處理外部Server傳遞的Packet時，可透過dstPort來找到對應的內網使用者。

此專案目前只支援常見之**ICMP Ping、TCP、UDP**協定(Protocol)轉譯功能，其他Layer 4 Protocol(e.g. DCCP、SCTP)和ICMP功能不確定是否可以轉譯成功。

測試方面，本專案主要利用`ping` 、 `iperf`、與自己撰寫之 HTTP Server/Client 來測試NAT功能是否正常。

### 網路拓撲

本專案使用之網路拓撲(Network Topology)為下圖所示：

<p align="center">
    <img src = "./doc/topology.jpg" alt = "topology">
</p>

其中，h1、h2 為內網(Private Network)使用者，h11、h22為公網(Public Network)之伺服器。
S1為h1和h2的對外Switch，S2假設為Core Network，S3為h11、h22的對外Switch。

將Topology建設好後，在未使用NAT功能的mininet模擬器中，輸入`pingall`指令會顯示h1、h2可互通，但無法跟h11、h22通訊，反之亦然。

<p align="center">
    <img src="doc\topology_fin_2025-05-06.png" alt="topology2">
</p>

## 2.環境介紹

- Virtual Box版本 ： 7.0.22
- VM版本          :  [P4 Tutorial Development 2023-01-1](https://drive.google.com/file/d/1uy5g0lHr1Cb0f9F-d5ujv44nZJepvI8S/view?usp=share_link)
- CPU             : Intel 11'th i7-1185G7
- NIC             : Intel Wi-Fi 6 AX201

## 3.運行方式

1. `cd nat/program` :切換目錄至程式碼位置
2. `make run`:編譯P4程式並運行mininet模擬器
3. 在mininet上輸入 `xterm h1 h2 h11 h22` 以叫出使用者指令界面
4. 根據測試內容運行對應的指令、程式
   - `iperf` 測試Client與Server之間的TCP/UDP網路狀態
      1. 在h11/h22輸入 `iperf -s`(TCP)或`iperf -s -u`(UDP)
      2. 在h1/h2輸入 `iperf -c 123.0.1.11`(TCP)或 `iperf -c 123.0.1.11 -u`(UDP)
   - `ping` 
      1. 在h1/h2輸入 `ping 123.0.1.11`
   - HTTP程式
      1. 在h11輸入`python3 server.py -p 80 -b 123.0.1.11`
      2. 在h1輸入 `python3 client.py -p 80 -u http://123.0.1.11 -i "想要的訊息"`

5. 測試完成後，在mininet輸入`exit`退出
6. 退出後，分別輸入`make stop` 與 `make clean`來停止mininet並刪除編譯檔案與log

## 4.重點技術
