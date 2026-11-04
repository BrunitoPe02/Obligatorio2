/* Obligatorio 2 - Parte 2.2: switch Ethernet P4 (v1model / BMv2).
 * Programa general: el mismo para todas las instancias de p4sw.
 * Lo que cambia entre switches es solo el plano de control (commands.txt).
 */
#include <core.p4>
#include <v1model.p4>

#define MAX_PORTS 16
#define BCAST_GRP 1

/*************************************************************************
 *  Encabezados
 *************************************************************************/
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

struct headers_t {
    ethernet_t ethernet;
}

struct metadata_t {
}

/*************************************************************************
 *  Parser
 *************************************************************************/
parser MyParser(packet_in pkt,
                out headers_t hdr,
                inout metadata_t meta,
                inout standard_metadata_t std_meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition accept;
    }
}

/*************************************************************************
 *  Verificacion de checksum
 *************************************************************************/
control MyVerifyChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

/*************************************************************************
 *  Ingress
 *************************************************************************/
control MyIngress(inout headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t std_meta) {

    // Contadores
    counter(MAX_PORTS, CounterType.packets_and_bytes) port_in_cnt;   // recibidos por puerto
    counter(1, CounterType.packets_and_bytes) unknown_drop_cnt;      // unicast desconocido descartado
    direct_counter(CounterType.packets_and_bytes) mac_fwd_cnt;       // hits por regla

    action drop() {
        mark_to_drop(std_meta);
    }

    action forward(bit<9> port) {
        std_meta.egress_spec = port;
    }

    action broadcast() {
        std_meta.mcast_grp = BCAST_GRP;
    }

    table mac_fwd {
        key = {
            hdr.ethernet.dstAddr : exact;
        }
        actions = {
            forward;
            broadcast;
            drop;
        }
        size = 256;
        default_action = drop();   // politica: unicast desconocido -> drop
        counters = mac_fwd_cnt;
    }

    apply {
        port_in_cnt.count((bit<32>) std_meta.ingress_port);

        if (hdr.ethernet.isValid()) {
            if (!mac_fwd.apply().hit) {
                unknown_drop_cnt.count(0);
            }
        } else {
            drop();
        }
    }
}

/*************************************************************************
 *  Egress
 *************************************************************************/
control MyEgress(inout headers_t hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t std_meta) {

    counter(MAX_PORTS, CounterType.packets_and_bytes) port_out_cnt;  // enviados por puerto

    apply {
        // No devolver una copia del broadcast por el puerto de entrada
        if (std_meta.egress_port == std_meta.ingress_port) {
            mark_to_drop(std_meta);
        } else {
            port_out_cnt.count((bit<32>) std_meta.egress_port);
        }
    }
}

/*************************************************************************
 *  Calculo de checksum
 *************************************************************************/
control MyComputeChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

/*************************************************************************
 *  Deparser
 *************************************************************************/
control MyDeparser(packet_out pkt, in headers_t hdr) {
    apply {
        pkt.emit(hdr.ethernet);
    }
}

V1Switch(MyParser(),
         MyVerifyChecksum(),
         MyIngress(),
         MyEgress(),
         MyComputeChecksum(),
         MyDeparser()) main;