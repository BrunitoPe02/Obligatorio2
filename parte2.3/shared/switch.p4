/* Obligatorio 2 - Parte 2.3: switch Ethernet P4 con politica de acceso (v1model / BMv2).
 * Programa general: el mismo para todas las instancias de p4sw.
 * Lo que cambia entre switches es solo el plano de control (commands.txt).
 */
#include <core.p4>
#include <v1model.p4>

#define MAX_PORTS 16
#define BCAST_GRP 1

const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_ARP  = 0x0806;
const bit<8>  PROTO_TCP = 6;


/*************************************************************************
 *  Encabezados
 *************************************************************************/

/* ETHERNET */
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

/* ARP */
header arp_t {
    bit<16> htype;     // tipo de hardware (1 = Ethernet)
    bit<16> ptype;     // tipo de protocolo (0x0800 = IPv4)
    bit<8>  hlen;      // largo de MAC (6)
    bit<8>  plen;      // largo de IP (4)
    bit<16> oper;      // 1 = request, 2 = reply
    bit<48> sha;       // MAC del emisor
    bit<32> spa;       // IP del emisor
    bit<48> tha;       // MAC del destino
    bit<32> tpa;       // IP del destino (la que se busca)
}

/* IPV4 */
header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

/* TCP */
header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}


struct headers_t {
    ethernet_t ethernet;
    arp_t      arp;
    ipv4_t     ipv4;
    tcp_t      tcp;
}

struct metadata_t {
    bit<1> is_guest;   // 1 = el paquete entró por un puerto de invitado
    bit<32> l3_dst;     // IP destino: ipv4.dstAddr, o arp.tpa si es ARP
    bit<8>  l4_proto;   // protocolo IP (6 = TCP); 0 si no es IPv4
    bit<16> l4_dport;   // puerto destino TCP; 0 si no es TCP

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
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            TYPE_ARP:  parse_arp;
            default:   accept;
        }
    }

    state parse_arp {
        pkt.extract(hdr.arp);
        meta.l3_dst = hdr.arp.tpa;
        transition accept;
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        meta.l3_dst   = hdr.ipv4.dstAddr;
        meta.l4_proto = hdr.ipv4.protocol;
        // Solo se extrae TCP si el encabezado IPv4 mide 20 bytes (ihl == 5, sin
        // opciones) y el paquete no es un fragmento posterior (fragOffset == 0).
        // En otro caso el encabezado TCP no esta donde el parser lo buscaria:
        // l4_dport queda en 0 y, para un invitado, la lista blanca lo descarta.
        transition select(hdr.ipv4.ihl, hdr.ipv4.fragOffset, hdr.ipv4.protocol) {
            (4w5, 13w0, PROTO_TCP): parse_tcp;
            default:                accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        meta.l4_dport = hdr.tcp.dstPort;
        transition accept;
    }
}

/* extraigo Ethernet; si es IPv4 voy a parse_ipv4, si es ARP voy a parse_arp; en IPv4, si el protocolo es TCP extraigo TCP */

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

    counter(2, CounterType.packets_and_bytes) guest_policy_cnt;   // [0] permitidos, [1] descartados
    direct_counter(CounterType.packets_and_bytes) guest_acl_cnt;  // aciertos por regla de guest_acl


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

        action set_guest() {
        meta.is_guest = 1;
    }

    table port_role {
        key = {
            std_meta.ingress_port : exact;   // por qué puerto entró el paquete
        }
        actions = {
            set_guest;
            NoAction;
        }
        size = MAX_PORTS;
        default_action = NoAction();         // puerto no cargado → no se marca
    }

        action acl_permit() {
        // no hace nada: el paquete sigue hacia el forwarding L2
    }

    action acl_deny() {
        mark_to_drop(std_meta);
    }

    table guest_acl {
        key = {
            hdr.ethernet.etherType : ternary;
            meta.l3_dst            : ternary;
            meta.l4_proto          : ternary;
            meta.l4_dport          : ternary;
        }
        actions = {
            acl_permit;
            acl_deny;
        }
        size = 64;
        default_action = acl_deny();   // lista blanca: lo que no coincide se descarta
        counters = guest_acl_cnt;
    }


    apply {
        port_in_cnt.count((bit<32>) std_meta.ingress_port);

        if (hdr.ethernet.isValid()) {
            bool allowed = true;
            port_role.apply();

            if (meta.is_guest == 1) {
                switch (guest_acl.apply().action_run) {
                    acl_permit: { guest_policy_cnt.count(0); }
                    acl_deny:   { guest_policy_cnt.count(1); allowed = false; }
                }
            }

            if (allowed) {
                if (!mac_fwd.apply().hit) {
                    unknown_drop_cnt.count(0);
                }
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
        pkt.emit(hdr.arp);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
    }
}

V1Switch(MyParser(),
         MyVerifyChecksum(),
         MyIngress(),
         MyEgress(),
         MyComputeChecksum(),
         MyDeparser()) main;