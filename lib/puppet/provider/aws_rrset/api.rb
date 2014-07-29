require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'puppet_x', 'bobtfish', 'ec2_api.rb'))


Puppet::Type.type(:aws_rrset).provide(:api, :parent => Puppet_X::Bobtfish::Ec2_api) do
  mk_resource_methods

  
  def self.new_from_aws(zone, item)
    name = "#{item.type} #{item.name}"
    new(
      :aws_item         => item,
      :name             => name,
      :ensure           => :present,
      :zone             => zone.name,
      :value            => array_to_puppet(item.resource_records.collect {|r| r[:value]}),
      :ttl              => item.ttl.to_s,
    )
  end
  def self.instances
    r53.hosted_zones.collect do |zone|
      zone.rrsets.collect {|item| new_from_aws(zone, item)}
    end.flatten
  end

  
  def create
    zone = self.class.find_hosted_zone_by_name(resource[:zone])
    split_name = resource[:name].split(' ')
    if split_name.length != 2
      raise 'AWS resource record set name MUST be in the form of "<type> <name>" - e.g. "CNAME foo.example.com."'
    end
    record_type, record_name = split_name
    zone.rrsets.create(
      record_name,
      record_type,
      :ttl => resource[:ttl].to_i,
      :resource_records => resource[:value].map{|v| {:value => v}},
    )
  end
  def destroy
    @property_hash[:aws_item].delete
  end

  def wait_until_ready(zone)
    until zone.change_info.status == 'PENDING'
      puts "Zone status is: #{zone.change_info.status}"
      sleep 1
    end
  end

end

