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
header l4port_t {
    Port_t srcPort;
    Port_t dstPort;
}
header icmp_t{
    bit<8> type;
    bit<8> code;
    bit<16> sum;
    bit<16> id;
    bit<16> seq;
}
struct metadata {
    /* empty */
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    icmp_t       icmp;
    l4port_t     port;

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
        transition select(hdr.ipv4.protocol){
            TYPE_TCP: parse_tcp;
            TYPE_UDP: parse_udp;
            TYPE_ICMP: parse_icmp;
            default: accept;
        }
    }
    state parse_tcp{
        packet.extract(hdr.port);
        transition accept;
    }
    state parse_udp{
        packet.extract(hdr.port);
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

register<bit<32>>(65535) nat_reg;
/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    bit<32> true_ip;
    bit<32> id;
    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipForward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }
    action ethForward(egressSpec_t port){
        standard_metadata.egress_spec = port;
    }
    action multicast(){
        standard_metadata.mcast_grp = 1;
    }
    action Trans(){
        nat_reg.read(true_ip,id);
        hdr.ipv4.dstAddr = true_ip;
    }
    table nat{
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            Trans;
            NoAction;
        } 
        const default_action = NoAction;
        const entries = {
            0x79000101 : Trans();
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

        if(hdr.icmp.isValid()){
            id = (bit<32>)hdr.icmp.id;
            nat.apply();
        }

        if (hdr.ipv4.isValid()) {
            ipCheck.apply();
        }else if(hdr.ethernet.isValid()){
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
        if(standard_metadata.egress_port == 3){
            if(hdr.icmp.isValid()){
                nat_reg.write((bit<32>)hdr.icmp.id,hdr.ipv4.srcAddr );
            }
            hdr.ipv4.srcAddr = 0x79000101;  // 0x79000101 = 121.0.1.1
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
            HashAlgorithm.csum16);
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
        packet.emit(hdr.port);
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
