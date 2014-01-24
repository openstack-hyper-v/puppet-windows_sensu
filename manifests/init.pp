# === Class: windows_sensu
#
# This module installs sensu on Windows systems. It also adds an entry to the
# PATH environment variable.
#
# === Parameters
#
# [*url*]
#   HTTP url where the installer is available. It defaults to main site.
# [*package*]
#   Package name in the system.
# [*file_path*]
#   This parameter is used to specify a local path for the installer. If it is
#   set, the remote download from $url is not performed. It defaults to false.
#
# === Examples
#
# class { 'windows_sensu': }
#
# class { 'windows_sensu':
#   $url     => 'http://192.168.1.1/files/sensu.exe',
#   $package => 'sensu version 1.8.0-preview201221022',
# }
#
# === Authors
# 
#
class windows_sensu (
  $url       = $::windows_sensu::params::url,
  $package   = $::windows_sensu::params::package,
  $file_path = false,
  $rabbitmq_port            = 5671,
  $rabbitmq_host            = 'localhost',
  $rabbitmq_user            = 'sensu',
  $rabbitmq_password        = '',
  $rabbitmq_vhost           = '/sensu',
  $rabbitmq_ssl_private_key = '/etc/sensu/ssl/key.pem',
  $rabbitmq_ssl_cert_chain  = '/etc/sensu/ssl/cert.pem',
  $subscriptions            = ["hyper-v"],
  $client_name              = $::fqdn,
  $client_custom            = {},
  $safe_mode                = true,
  
) inherits windows_sensu::params {

  if $file_path {
    $sensu_installer_path = $file_path
  } else {
    $sensu_installer_path = "${::temp}\\${package}.msi"
    windows_common::remote_file{'sensu':
      source      => $url,
      destination => $sensu_installer_path,
      before      => Package[$package],
    }
  }
 
  windows_common::configuration::feature { 'NET-Framework-Core':
    ensure   => present,
  } 

  package { $package:
    ensure          => installed,
    source          => $sensu_installer_path,
    install_options => ['/passive'],
    require         => Windows_Common::Configuration::Feature['NET-Framework-Core'],
  }
  
  file_line { 'sensu_conf_arg':
    path    => 'c:/opt/sensu/bin/sensu-client.xml',
    match   => "<arguments*",
    line    => "<arguments>C:\\opt\\sensu\\embedded\\bin\\sensu-client -d C:\\etc\\sensu\\conf.d -l C:\\opt\\sensu\\sensu-client.log</arguments>",
    ensure  => present,
    require => Package[$package],
    before  => Exec['sc_create_sensu_service'],
  }
 
  file{'c:/etc': ensure  => directory, }
  file{'c:/etc/sensu': ensure => directory, }
  file{'c:/etc/sensu/ssl': ensure => directory,}
  file{'c:/etc/sensu/conf.d': ensure => directory, }
  File['c:/etc'] -> File['c:/etc/sensu'] -> File['c:/etc/sensu/ssl'] ->  File['c:/etc/sensu/conf.d']
 
  file { 'c:/etc/sensu/ssl/cert.pem':
    ensure  => present,
    source  => "puppet:///extra_files/sensu/cert.pem",
    require => File['c:/etc', 'c:/etc/sensu', 'c:/etc/sensu/conf.d', 'c:/etc/sensu/ssl'],
  }

  windows_common::remote_file{'key.pem':
    source      => "http://10.21.7.22/sensu/key.pem",
    destination => 'c:/etc/sensu/ssl/key.pem',
    require     => File['c:/etc', 'c:/etc/sensu', 'c:/etc/sensu/conf.d', 'c:/etc/sensu/ssl'],
  }
 
  #file { 'c:/etc/sensu/ssl/key.pem':
   # ensure  => present,
    #source  => "puppet:///extra_files/sensu/key.pem",
    #source   => "http:///10.21.7.22/tim/sensu/key.pem",
    #require => File['c:/etc', 'c:/etc/sensu', 'c:/etc/sensu/conf.d', 'c:/etc/sensu/ssl'],
    #source_permissions  => ignore,
  #}

  file { 'c:/etc/sensu/conf.d/rabbitmq.json':
    ensure  => present,
    before  => Sensu_rabbitmq_config[$::fqdn],
    require => File['c:/etc', 'c:/etc/sensu', 'c:/etc/sensu/conf.d', 'c:/etc/sensu/ssl'],
  }
    
  sensu_rabbitmq_config { $::fqdn:
    ensure          => present,
    port            => $windows_sensu::rabbitmq_port,
    host            => $windows_sensu::rabbitmq_host,
    user            => $windows_sensu::rabbitmq_user,
    password        => $windows_sensu::rabbitmq_password,
    vhost           => $windows_sensu::rabbitmq_vhost,
    ssl_cert_chain  => $windows_sensu::rabbitmq_ssl_cert_chain,
    ssl_private_key => $windows_sensu::rabbitmq_ssl_private_key,
  }
  
  file { 'c:/etc/sensu/conf.d/client.json':
    ensure  => $ensure,
    before  => Sensu_client_config[$::fqdn],
    require => File['c:/etc', 'c:/etc/sensu', 'c:/etc/sensu/conf.d', 'c:/etc/sensu/ssl'],
  }

  $client_address  = inline_template("<%= `nslookup ${::fqdn} | grep '10.21.7' | cut -d ':' -f2 |  tr '\n' '\t' | sed 's/^[ \t]*//;s/[ \t]*$//'` -%>")

  notify { "client address is ${client_address}": }

  sensu_client_config { $::fqdn:
    ensure        => present,
    client_name   => $windows_sensu::client_name,
    address       => $windows_sensu::client_address,
    subscriptions => $windows_sensu::subscriptions,
    safe_mode     => $windows_sensu::safe_mode,
    custom        => $windows_sensu::client_custom,
  }
  
  exec { 'sc_create_sensu_service':
    command   => 'sc.exe create sensu-client start= delayed-auto binPath= c:\opt\sensu\bin\sensu-client.exe DisplayName= "Sensu Client"',
    path      => "${path}",
    logoutput => true,
    require   => [Package[$package],File['c:/etc/sensu/conf.d/client.json'],File['c:/etc/sensu/conf.d/rabbitmq.json']],
    unless    => 'sc.exe getdisplayname sensu-client',
  }

  service { 'sensu-client':
    ensure    => running,
    enable    => true,
    require   => Exec[sc_create_sensu_service],
    subscribe => [ File['c:/etc/sensu/conf.d/client.json'],File['c:/etc/sensu/conf.d/rabbitmq.json'] ],
  }
}

