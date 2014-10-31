# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  config.vm.box = "ops_precise64"
  config.vm.box_url = "http://opscode-vm-bento.s3.amazonaws.com/vagrant/virtualbox/opscode_ubuntu-12.04_chef-provisionerless.box"
  config.vm.provision :shell, :path => "vagrant_provision.sh", :privileged => false

  config.vm.network :forwarded_port, guest: 80, host: 8080 # HTTP
  config.vm.network :forwarded_port, guest: 443, host: 4443 # HTTPS
  config.vm.network :forwarded_port, guest: 3000, host: 3030
  config.vm.network :forwarded_port, guest: 9200, host: 9292

  config.vm.synced_folder "./", "/vagrant", owner: 'vagrant', group: 'vagrant', mount_options: ['fmode=777', 'dmode=777']

end
