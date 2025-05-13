// SPDX-License-Identifier: Apache-2.0
/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;
const bit<8>  TYPE_TCP = 0x06;
const bit<8>  TYPE_UDP = 0x11;
const bit<8>  TYPE_ICMP = 0x01;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
typedef bit<16> Port_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}
header icmp_t{  // icmp header
    bit<8> type;
    bit<8> code;
    bit<16> sum;
    bit<16> id;
    bit<16> seq;
}
header tcp_t{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<1>  cwr;
    bit<1>  ece;
    bit<1>  urg;
    bit<1>  ack;
    bit<1>  psh;
    bit<1>  rst;
    bit<1>  syn;
    bit<1>  fin;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}
header udp_t{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> len;
    bit<16> checksum;
}
struct metadata {
    /* empty */
    bit<16> Length;
    bit<16> cur_port;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    icmp_t       icmp;
    tcp_t        tcp;
    udp_t        udp;

}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4); 
        meta.Length = hdr.ipv4.totalLen - (bit<16>)(hdr.ipv4.ihl)*4; // for tcp checksum update
        transition select(hdr.ipv4.protocol){
            TYPE_TCP: parse_tcp;
            TYPE_UDP: parse_udp;
            TYPE_ICMP: parse_icmp;
            default: accept;
        }
    }
    state parse_tcp{ 
        packet.extract(hdr.tcp);
        transition accept;
    }
    state parse_udp{ 
        packet.extract(hdr.udp);
        transition accept;
    }
    state parse_icmp{
        packet.extract(hdr.icmp);
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

//        ip  <-  port             65535 : the max port number 
register<bit<32>>(65535) ip_reg;   //store the port/original port map to ipv4 
register<bit<32>>(65535) port_reg; //store the port/ip map to ipv4 

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    //ture_ip       -> access the internal ip associated with the specified port.
    //ture_port     -> access the internal port associated with the specified port.
    //id            -> specified port, can be icmp's identifier or tcp/udp's dstPort.
    //read(val,idx) -> read register's idx'th place and store in val.

    bit<32> true_ip; 
    bit<32> true_port;
    bit<16> id = 0x0000;      


    action drop() {
        mark_to_drop(standard_metadata);
    }

    action port_hash(bit<16> src,bit<16> dst){
        hash(
        meta.cur_port,
        HashAlgorithm.crc16,
        (bit<16>)1025,
            {
                hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr,
                hdr.ipv4.protocol,
                src,
                dst
            },
        (bit<16>) 64509
        );
    }
    
    action ipForward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    action ethForward(egressSpec_t port){//for intranet communication
        standard_metadata.egress_spec = port;
    }

    action multicast(){ //for intranet communication
        standard_metadata.mcast_grp = 1;
    }

    action Trans_TCP(){
        ip_reg.read(true_ip,(bit<32>)id);
        port_reg.read(true_port,(bit<32>)id);
        hdr.ipv4.dstAddr = true_ip;
        hdr.tcp.dstPort = (bit<16>)true_port;
    }

    action Trans_UDP(){
        ip_reg.read(true_ip,(bit<32>)id);
        port_reg.read(true_port,(bit<32>)id);
        hdr.ipv4.dstAddr = true_ip;
        hdr.udp.dstPort = (bit<16>)true_port;
    }

    action Trans_ICMP(){
        ip_reg.read(true_ip,(bit<32>)id);
        hdr.ipv4.dstAddr = true_ip;
    }

    table nat{
        key = {
            hdr.ipv4.dstAddr: lpm;
            hdr.ipv4.protocol: exact;
        }
        actions = {
            Trans_TCP;
            Trans_UDP;
            Trans_ICMP;
            NoAction;
        } 
        const default_action = NoAction;
        const entries = {
            (0x79000101,TYPE_TCP) : Trans_TCP();
            (0x79000101,TYPE_ICMP): Trans_ICMP();
            (0x79000101,TYPE_UDP) : Trans_UDP();
        }
    }
    table debug{
        key = {
            hdr.ipv4.srcAddr : exact;
            hdr.ipv4.dstAddr : exact;
            hdr.ipv4.protocol : exact;
            hdr.tcp.srcPort : exact;
            hdr.tcp.dstPort : exact;
            hdr.udp.srcPort : exact;
            hdr.udp.dstPort : exact;
        }
        actions = {
            NoAction;
        }

    }
    
    table ipCheck {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipForward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }

    table ethCheck{
        key = {
            hdr.ethernet.dstAddr: exact;
        }
        actions ={
            multicast;
            ethForward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = multicast;
    }

    apply {
        bit<16> src;
        // transportation layer
        // change nat search index
        if(hdr.icmp.isValid()){
            id = hdr.icmp.id;

        }else if(hdr.tcp.isValid()){
            id = hdr.tcp.dstPort;
            src = hdr.tcp.srcPort;
            
        }else if(hdr.udp.isValid()){
            id = hdr.udp.dstPort;
            src = hdr.udp.srcPort;
        }

        // use nat table
        if(nat.apply().miss){
            if(hdr.ipv4.protocol != TYPE_ICMP){
                port_hash(src,id);
                // debug.apply();
            }else{
                meta.cur_port = hdr.icmp.id;
            }
            // check whether the switch out port is used.
            bit<32> checker;
            ip_reg.read(checker,(bit<32>)meta.cur_port);

            if(checker != 0 && !hdr.tcp.isValid()){
                // if used, drop the packet
                drop();
            }

        }else{
            if(id != 0x0000){
                // release the out port
                if((hdr.tcp.isValid() && hdr.tcp.fin == 1) || (!hdr.tcp.isValid())){
                    ip_reg.write((bit<32>)id,32w0);
                    port_reg.write((bit<32>)id,32w0);
                }
                
            }
        }

        // network layer
        if (hdr.ipv4.isValid()) {
            ipCheck.apply();
        }else if(hdr.ethernet.isValid()){ // multicast
            ethCheck.apply();
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  
        if(standard_metadata.egress_port == 3){ // WAN port on switch 

            // write the specified ip/port number on register.
            bit<32> temp_ip = hdr.ipv4.srcAddr;
            hdr.ipv4.srcAddr = 0x79000101;  // 0x79000101 = 121.0.1.1

            if(hdr.icmp.isValid()){
                ip_reg.write((bit<32>)meta.cur_port,temp_ip);
            }else if(hdr.tcp.isValid()){
                ip_reg.write((bit<32>)meta.cur_port, temp_ip);
                port_reg.write((bit<32>)meta.cur_port,(bit<32>)hdr.tcp.srcPort);
                hdr.tcp.srcPort = meta.cur_port;
            }else if(hdr.udp.isValid()){
                ip_reg.write((bit<32>)meta.cur_port, temp_ip);
                port_reg.write((bit<32>)meta.cur_port,(bit<32>)hdr.udp.srcPort);
                hdr.udp.srcPort = meta.cur_port;
            }
            
        }
    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
        update_checksum(
            hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16
        );

        update_checksum_with_payload(
            hdr.tcp.isValid(),
            { 
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr,
              8w0,
              hdr.ipv4.protocol,
              meta.Length,
              hdr.tcp.srcPort,
              hdr.tcp.dstPort,
              hdr.tcp.seqNo,
              hdr.tcp.ackNo,
              hdr.tcp.dataOffset,
              hdr.tcp.res,
              hdr.tcp.cwr,
              hdr.tcp.ece,
              hdr.tcp.urg,
              hdr.tcp.ack,
              hdr.tcp.psh,
              hdr.tcp.rst,
              hdr.tcp.syn,
              hdr.tcp.fin,
              hdr.tcp.window,
              16w0,
              hdr.tcp.urgentPtr },
            hdr.tcp.checksum,
            HashAlgorithm.csum16
        );

        update_checksum_with_payload(
            hdr.udp.isValid(),
            {
                hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr,
                8w0,
                hdr.ipv4.protocol,
                meta.Length,
                hdr.udp.srcPort,
                hdr.udp.dstPort,
                hdr.udp.len
            },
            hdr.udp.checksum,
            HashAlgorithm.csum16
        );
        // since icmp's checksum will not change when ip changed.
        // there is for us to add update_checksum funcion.

    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.icmp);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
