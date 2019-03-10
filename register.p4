#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_NSH = 0x894f;
const bit<16> TYPE_IPV4 = 0x800;
const bit<16> TYPE_ETHER = 0x6558;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;



header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}


header nsh_t {
    bit<2>    ver;
    bit<1>    oam;
    bit<1>    un1;
    bit<6>    ttl;
    bit<6>    len;
    bit<4>    un4;
    bit<4>    MDtype;
    bit<16>   Nextpro;
    bit<24>   spi;
    bit<8>    si;
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


struct metadata {
    bit<24>    metadata_spi;
    bit<8>     metadata_si;
    bit<1>     metadata_nsh;
    bit<48>    delay;
}

struct headers {
    ethernet_t   out_ethernet;
    nsh_t        nsh;
    ethernet_t   in_ethernet;
    ipv4_t       ipv4;
}


/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
		        inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_out_ethernet;
    }

    state parse_out_ethernet {
        packet.extract(hdr.out_ethernet);
        transition select(hdr.out_ethernet.etherType) {
            TYPE_NSH: parse_nsh;
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_nsh {
        packet.extract(hdr.nsh);
        transition select(hdr.nsh.Nextpro) {
            TYPE_ETHER: parse_in_ethernet;
            default: accept;
        }
    }

    state parse_in_ethernet {
        packet.extract(hdr.in_ethernet);
        transition select(hdr.in_ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta
) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
		  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    action drop() {
        mark_to_drop();
    }
/*
    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }
*/



    action si_decrease(egressSpec_t port) {
	    meta.metadata_si = meta.metadata_si - 1;
	    standard_metadata.egress_spec = port;
    }

    action loopback() {  
        resubmit(meta);
    }

    action change_hdr_to_meta() {
	    meta.metadata_spi = hdr.nsh.spi;
	    meta.metadata_si = hdr.nsh.si;	
	}        

    action add_nsh() {
        meta.metadata_nsh = 1;
        hdr.nsh.setValid();
        hdr.in_ethernet.setValid();
        standard_metadata.egress_spec = 2;
    }

    action l2_forward(egressSpec_t port, macAddr_t dstAddr) {
        standard_metadata.egress_spec = port;
        hdr.out_ethernet.srcAddr = hdr.out_ethernet.dstAddr;
        hdr.out_ethernet.dstAddr = dstAddr;
               
    }

    action pass() {
        meta.metadata_si = meta.metadata_si - 1;
    }

    register<bit<48>>(16384) r;
    register<bit<48>>(16384) c;
    register<bit<48>>(16384) d;
    //counter(8192, CounterType.packets) c;

    action delay_calculation(out bit<48>delay){
        bit<48> send_time;
        bit<48> receive_time;
        r.read(send_time,0); // send_time = r[0]
        receive_time = standard_metadata.ingress_global_timestamp;
        delay = receive_time - send_time;
        d.write(0,delay);
    }

    action sf_forward(egressSpec_t port) {
        bit<48> index;
        bit<48> send_time;
        // 0 <- hdr.flownumber
        c.read(index, 0); //index = c[0]
        send_time = standard_metadata.ingress_global_timestamp;
        r.write((bit<32>)index,send_time);
        standard_metadata.egress_spec = port;
        c.write(0, index+1);
    }


    table precheck{
        key = {
            standard_metadata.instance_type : exact;
        }
        actions = {
            change_hdr_to_meta;
            drop;
            NoAction;
        }
        default_action = NoAction();
    }

/*
    table delay_cal {
        key = {

        }
        actions = {
            delay_calculation;
        }
        size = 1024;
        default_action = NoAction();
    }
*/

    table sff {
        key = {
            meta.metadata_spi: exact;
            meta.metadata_si: exact;
        }
        actions = {
            loopback;
            //ipv4_forward;
            l2_forward;
            sf_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        if (hdr.nsh.un4 != 0){
            delay_calculation(meta.delay);
        }
        precheck.apply();
        sff.apply();
        
    }

    
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
		 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {

    }

}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {

    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.out_ethernet);
	    packet.emit(hdr.nsh);
        packet.emit(hdr.in_ethernet);      
        packet.emit(hdr.ipv4);
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
