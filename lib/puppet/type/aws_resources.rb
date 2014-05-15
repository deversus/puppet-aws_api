require 'puppet'
require 'puppet/parameter/boolean'

Puppet::Type.newtype(:aws_resources) do
  @doc = "A blatant ripoff of the resources type with support for using
          credentials in the 'generate' method"

  newparam(:name) do
    desc "The name of the type to be managed."

    validate do |name|
      raise ArgumentError, "Could not find resource type '#{name}'" unless Puppet::Type.type(name)
    end

    munge { |v| v.to_s }
  end

  newparam(:purge, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    desc "Purge unmanaged resources.  This will delete any resource
      that is not specified in your configuration
      and is not required by any specified resources.
      Purging ssh_authorized_keys this way is deprecated; see the
      purge_ssh_keys parameter of the user type for a better alternative."

    defaultto :false

    validate do |value|
      if munge(value)
        unless @resource.resource_type.respond_to?(:instances)
          raise ArgumentError, "Purging resources of type #{@resource[:name]} is not supported, since they cannot be queried from the system"
        end
        raise ArgumentError, "Purging is only supported on types that accept 'ensure'" unless @resource.resource_type.validproperty?(:ensure)
      end
    end
  end

  newparam(:unless_system_user) do
    desc "This keeps system users from being purged.  By default, it
      does not purge users whose UIDs are less than or equal to 500, but you can specify
      a different UID as the inclusive limit."

    newvalues(:true, :false, /^\d+$/)

    munge do |value|
      case value
      when /^\d+/
        Integer(value)
      when :true, true
        500
      when :false, false
        false
      when Integer; value
      else
        raise ArgumentError, "Invalid value #{value.inspect}"
      end
    end

    defaultto {
      if @resource[:name] == "user"
        500
      else
        nil
      end
    }
  end

  newparam(:unless_uid) do
     desc "This keeps specific uids or ranges of uids from being purged when purge is true.
       Accepts ranges, integers and (mixed) arrays of both."

     munge do |value|
       case value
       when /^\d+/
         [Integer(value)]
       when Integer
         [value]
       when Range
         [value]
       when Array
         value
       when /^\[\d+/
         value.split(',').collect{|x| x.include?('..') ? Integer(x.split('..')[0])..Integer(x.split('..')[1]) : Integer(x) }
       else
         raise ArgumentError, "Invalid value #{value.inspect}"
       end
     end
   end

  newparam(:account) do
    desc "The namevar of the credentials that need to be used to perform prefetch."
  end


  def check(resource)
    @checkmethod ||= "#{self[:name]}_check"
    @hascheck ||= respond_to?(@checkmethod)
    if @hascheck
      return send(@checkmethod, resource)
    else
      return true
    end
  end

  def able_to_ensure_absent?(resource)
      resource[:ensure] = :absent
  rescue ArgumentError, Puppet::Error
      err "The 'ensure' attribute on #{self[:name]} resources does not accept 'absent' as a value"
      false
  end

  # Generate any new resources we need to manage.  This is pretty hackish
  # right now, because it only supports purging.
  def generate
    credentials = catalog.resources.find_all do |r|
      r.is_a?(Puppet::Type.type(:aws_credential)) && r[:name] == self[:account]
    end.first

    return [] unless self.purge?
    resource_type.instances({:access_key => credentials[:access_key], :secret_key => credentials[:secret_key]}).
      reject { |r| catalog.resource_refs.include? r.ref }.
      select { |r| check(r) }.
      select { |r| r.class.validproperty?(:ensure) }.
      select { |r| able_to_ensure_absent?(r) }.
      each { |resource|
        @parameters.each do |name, param|
          resource[name] = param.value if param.metaparam?
        end

        # Mark that we're purging, so transactions can handle relationships
        # correctly
        resource.purging
      }
  end

  def resource_type
    unless defined?(@resource_type)
      unless type = Puppet::Type.type(self[:name])
        raise Puppet::DevError, "Could not find resource type"
      end
      @resource_type = type
    end
    @resource_type
  end

  # Make sure we don't purge users with specific uids
  def user_check(resource)
    return true unless self[:name] == "user"
    return true unless self[:unless_system_user]
    resource[:audit] = :uid
    current_values = resource.retrieve_resource
    current_uid = current_values[resource.property(:uid)]
    unless_uids = self[:unless_uid]

    return false if system_users.include?(resource[:name])

    if unless_uids && unless_uids.length > 0
      unless_uids.each do |unless_uid|
        return false if unless_uid == current_uid
        return false if unless_uid.respond_to?('include?') && unless_uid.include?(current_uid)
      end
    end

    current_uid > self[:unless_system_user]
  end

  def system_users
    %w{root nobody bin noaccess daemon sys}
  end
end