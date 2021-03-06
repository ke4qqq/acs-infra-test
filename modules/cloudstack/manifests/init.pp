#Apache Cloudstack - Module for the Management Server and Agent
#

class common::data {
  $nameservers = ["10.223.75.10", "10.223.110.254", "8.8.8.8"]
  $puppetmaster = "10.223.75.10"
}

class cloudstack {
  case $operatingsystem  {
    centos: { include cloudstack::no_selinux }
    redhat: { include cloudstack::no_selinux }
  }
  include cloudstack::repo
  include cloudstack::ports
  include cloudstack::files
  include common::data
  include mysql

  #TODO: Update to latest systemvm urls
  $sysvm_url_kvm = "http://download.cloud.com/releases/2.2.0/systemvm.qcow2.bz2"
  $sysvm_url_xen = "http://download.cloud.com/releases/2.2.0/systemvm.vhd.bz2"

  $packages = ["wget"] 
  package { $packages: 
      ensure => installed,
  }
  
  #For mounting the secondary and ISO 
  package { "nfs-utils":
    name     => $operatingsystem ? {
      centos => "nfs-utils",
      redhat => "nfs-utils",
      debian => ["nfs-common", "nfs-kernel-server"],
      ubuntu => ["nfs-common", "nfs-kernel-server"]
    },
    ensure => installed,
  }

  #Needed for systemvm.iso
  package { "genisoimage":
    ensure => installed,
  }

  service { "nfs":
    name      => $operatingsystem? {
      ubuntu  => "nfs-kernel-server",
      default => "nfs"
    },
    ensure  => running,
    require => Package["nfs-utils"],
  }

  case $operatingsystem {
    centos,redhat : {
      $packagelist =  [ "cloud-server", "cloud-client"]
      package { $packagelist:
         ensure  => installed,
         require => Yumrepo["cstemp"],
      }
      file { "/etc/yum.repos.d/cstemp.repo":
        ensure => absent,
      }
    }
    ubuntu, debian: {
      $packagelist =  [ "cloud-server", "cloud-client"]
      package { $packagelist:
         ensure  => latest,
         require => File["/etc/apt/sources.list.d/cloudstack.list"],
      }
    }
    fedora : {
    }
  }

  exec {"cloud-setup-databases cloud:cloud@localhost --deploy-as=root":
    creates => "/var/lib/mysql/cloud",
  }
  exec {"cloud-setup-management":
    creates => "/var/run/cloud-management.pid",
  }
  service { "cloud-management":
    ensure => running,
  }
}

class cloudstack::agent {
  case $operatingsystem  {
    centos: { include cloudstack::no_selinux }
    redhat: { include cloudstack::no_selinux }
  }
  include cloudstack::repo
  include cloudstack::ports
  include cloudstack::files
  include common::data

  case $operatingsystem {
    centos,redhat : {
      $packagelist =  [ "cloud-agent" ]
      package { $packagelist:
         ensure  => installed,
         require => Yumrepo["cstemp"],
      }
    }
    ubuntu, debian: {
      $packagelist =  [ "cloud-agent" ]
      package { $packagelist:
         ensure  => latest,
         require => [File["/etc/apt/sources.list.d/cloudstack.list"], Exec["apt-get update"]],
      }
    }
    fedora : {
    }
  }

  exec { "cloud-setup-agent":
    creates  => "/var/log/cloud/setupAgent.log",
    require => [ Package[cloud-agent],
    Package[NetworkManager],
    File["/etc/sudoers"],
    File["/etc/cloud/agent/agent.properties"],
    File["/etc/hosts"],
    File["/etc/resolv.conf"],
    Service["network"], ]
  }

  file { "/etc/cloud/agent/agent.properties":
    ensure   => present,
    require => Package[cloud-agent],
    content  => template("cloudstack/agent.properties")
  }


  service { network:
    ensure    => running,
    hasstatus => true, 
    require  => Package[NetworkManager]
  }

  package { NetworkManager:
    ensure => absent,
  }
}

class cloudstack::no_selinux {
  file { "/etc/selinux/config":
    source  => "puppet:///cloudstack/config",
  }
  exec { "/usr/sbin/setenforce 0":
    onlyif => "/usr/sbin/getenforce | grep Enforcing",
  }
}

class cloudstack::repo {
  #TODO: Repo replace from nodes.pp
  $yumrepo = "puppet:///cloudstack/yumrepo"
  #Wido D. Hollander's repo
  $aptrepo = "http://cloudstack.apt-get.eu/ubuntu"
  $aptkey = "http://cloudstack.apt-get.eu/release.asc"

  case $operatingsystem {
    centos,redhat : {
      file { "/tmp/cloudstack" :
        source  => "puppet:///cloudstack/yumrepo",
        recurse => true,
        owner   => "root",
        mode    => 0644,
        group   => "root",
        ensure  => directory,
        path    => "/tmp/cloudstack",
      }
      yumrepo { "cstemp":
        baseurl  => "file:///tmp/cloudstack",
        enabled  => 1,
        gpgcheck => 0,
        name     => "cstemp",
      	require => File["/tmp/cloudstack"],
      }
    }
    ubuntu, debian: {
      file { "/etc/apt/sources.list.d/cloudstack.list":
        ensure  => present,
        content => "deb ${aptrepo} ${lsbdistcodename} 4.0",
      }
      exec { "wget -O - ${aptkey} | apt-key add -": 
        path => ["/usr/bin", "/bin"],
      }
      exec { "apt-get update":
        path => ["/usr/bin", "/bin"],
      }
    }
    fedora : {
    }
  }
}

class cloudstack::ports {
  iptables { "apiport":
    proto => "tcp",
    dport => [8096, 8080, 9090],
    jump  => "ACCEPT",
  }

  iptables { "mysqlport":
    proto => "tcp",
    dport => 3306,
    jump  => "ACCEPT",
  }

  iptables { "nfsudp":
    proto => "udp",
    dport => 2049,
    jump  => "ACCEPT",
  }

  iptables { "nfstcp":
    proto => "tcp",
    dport => 2049,
    jump  => "ACCEPT",
  }
}

class cloudstack::files {
  include common::data
  $nameservers = $common::data::nameservers
  file { "/etc/sudoers":
    source => "puppet:///cloudstack/sudoers",
    mode   => 440,
    owner  => root,
    group  => root,
  }

  file { "/etc/hosts":
    content => template("cloudstack/hosts"),
  }

  host { "infra.cloudstack.org":
    ip           => $puppetmaster,
    host_aliases => ["infra", "puppet"]
  }

  file { "/etc/resolv.conf":
    content => template("cloudstack/resolv.conf"),
  }

  case $operatingsystem {
    redhat,centos: { 
    file { "/etc/sysconfig/network":
      content => template("cloudstack/network"),
    }
    }
    default: {}
  }
}
