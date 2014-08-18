require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'puppet_x', 'bobtfish', 'ec2_api.rb'))

Puppet::Type.type(:aws_s3_bucket).provide(:api, :parent => Puppet_X::Bobtfish::Ec2_api) do
  mk_resource_methods

  def self.instances_for_region(region)
    s3(region).buckets
  end
  def instances_for_region(region)
    self.class.instances_for_region region
  end
  def self.new_from_aws(region_name, item)
    
    new(
      :aws_item         => item,
      :name             => item.name,
      :ensure           => if item.exists? then :present else :absent end,
      :region           => region_name,
    )
  end

  def self.instances
    regions.collect do |region_name|
      instances_for_region(region_name).collect { |item|
        new_from_aws(region_name, item)
      }
    end.flatten
  end

  read_only(:region)

  

  def create
    s3(resource[:region]).buckets.create(resource[:name],
      :location_constraint => resource[:region]
    )
    
  end
  def destroy
    aws_item.delete
    @property_hash[:ensure] = :absent
  end
  def purge
    aws_item.delete!
    @property_hash[:ensure] = :purged
  end
  
end

