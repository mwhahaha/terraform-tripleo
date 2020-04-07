provider "libvirt" {
    uri = "qemu:///system"
}

resource "libvirt_network" "management" {
    name = "management"
    domain = "management.local"
    mode = "nat"
    addresses = ["10.109.0.0/24"]
    bridge = "mgmt"
    dns {
        enabled = true
    }
}

resource "libvirt_network" "provision" {
    name = "provision"
    mode = "none"
    bridge = "prov"
}

resource "libvirt_network" "internal" {
    name = "internal"
    mode = "none"
    bridge = "inter"
}

resource "libvirt_network" "storage" {
    name = "storage"
    mode = "none"
    bridge = "stor"
}

resource "libvirt_network" "tenant" {
    name = "tenant"
    mode = "none"
    bridge = "ten"
}

resource "libvirt_network" "external" {
    name = "external"
    mode = "none"
    bridge = "ext"
}

resource "libvirt_volume" "centos-8-qcow2" {
    name = "centos-8-qcow2"
    source = "${path.module}/images/CentOS-8-GenericCloud-8.1.1911-20200113.3.x86_64.qcow2"
    format = "qcow2"
}

resource "libvirt_volume" "ipxe-qcow2" {
    name = "ipxe-boot-qcow2"
    source = "${path.module}/images/ipxe-boot.qcow2"
    format = "qcow2"
}

resource "libvirt_volume" "vol-undercloud" {
    name = "vol-undercloud"
    # disk size in bytes
    # https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/volume.html.markdown#argument-reference
    size = 80000000000
    base_volume_id = libvirt_volume.centos-8-qcow2.id
    pool = "ssd"
}

resource "libvirt_volume" "vol-baremetal" {
    count = 4
    name = "vol-baremetal-${count.index}"
    # disk size in bytes
    # https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/volume.html.markdown#argument-reference
    size = 50000000000
    base_volume_id = libvirt_volume.ipxe-qcow2.id
    pool = "ssd"
}

data "template_file" "user_data" {
    template = file("${path.module}/configs/cloud-init.cfg")
}

resource "libvirt_cloudinit_disk" "cloud" {
    name = "cloud.iso"
    user_data = data.template_file.user_data.rendered
}

resource "libvirt_domain" "domain-undercloud" {
    name = "domain-undercloud"
    memory = "16384"
    vcpu = 4
    # cloud-init
    cloudinit = libvirt_cloudinit_disk.cloud.id

    network_interface {
        network_id = libvirt_network.management.id
        addresses = ["10.109.0.2"]
    }

    network_interface {
        network_id = libvirt_network.provision.id
        addresses  = ["192.168.24.1"]
    }

    disk {
        volume_id = libvirt_volume.vol-undercloud.id
    }

    console {
        type = "pty"
        target_type = "serial"
        target_port = "0"
    }

    graphics {
        type = "vnc"
        listen_type = "address"
        autoport = true
    }
}

resource "libvirt_domain" "domain-baremetal" {
    count = 4
    name = "domain-baremetal-${count.index}"
    memory = "16384"
    vcpu = 2

    network_interface {
        network_id = libvirt_network.provision.id
        addresses  = ["192.168.24.1"]
    }

    disk {
        volume_id = element(libvirt_volume.vol-baremetal.*.id, count.index)
    }

    console {
        type = "pty"
        target_type = "serial"
        target_port = "0"
    }

    graphics {
        type = "vnc"
        listen_type = "address"
        autoport = true
    }
}

#resource "null_resource" "vbmc-baremetal" {
#    count = 4
#    provisioner "local-exec" {
#        command = "vbmc add domain-baremetal-${count.index} --address 0.0.0.0 --port ${16000 + count.index} --username admin --password password; vbmc start domain-baremetal-${count.index}"
#    }
#    provisioner "local-exec" {
#        # command = "vbmc stop domain-baremetal-${count.index}; vbmc delete domain-baremetal-${count.index}"
#        command = "vbmc delete domain-baremetal-${count.index}"
#        when = destroy
#    }
#    depends_on = [ libvirt_domain.domain-baremetal ]
#}

resource "null_resource" "nodes-json" {
    provisioner "local-exec" {
        command = "bash gen_json.sh > nodes.json"
    }
    depends_on = [ libvirt_domain.domain-baremetal ]
}

terraform {
    required_version = ">= 0.12"
}
