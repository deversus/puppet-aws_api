#!/usr/bin/env rspec
require 'spec_helper'

type_class = Puppet::Type.type(:aws_test_creds)
provider_class = type_class.provider(:test)


describe provider_class do
  let(:instances) { provider_class.instances }

  it('does not have any instances') do
    expect(instances.size).to eql 0
  end
end

describe type_class do
  params = {:name => "baz", :account => "bar"}
  credential_hash = {:name => "bar", :access_key => "baz", :secret_key => "foo"}
  let(:credentials) { Puppet::Type.type(:aws_credential).new({
    :name => "baz",
    :access_key => "foo",
    :secret_key => "bar"
  })}
  let(:provider) { provider_class.new }
  let(:catalog) { Puppet::Resource::Catalog.new }
  let(:resource) {
    resource = mock('object')
    resource.expects(:catalog).at_least_once.returns(catalog)
    resource.expects(:[]).at_least_once.returns('baz')
    resource
  }
  it "should be able to create an instance" do
    described_class.new(params).should_not be_nil
  end

  context "with credentials added" do
    before :each do
      catalog.add_resource credentials
      catalog.add_resource described_class.new(params)
      provider.expects(:resource).at_least_once.returns(resource)
    end

    it "should make credentials queryable from the catalog" do
      lambda { provider.create }.should_not raise_error
    end
    it "should not access the default credentials" do
      lambda { provider.create }.should_not raise_error
      provider.get_creds.should eq({
        :access_key_id => "foo", :secret_access_key => "bar"})
    end
  end
  context "without credentials added" do
    it "should use the default credentials" do
      catalog.add_resource described_class.new(params)
      lambda { provider.create }.should_not raise_error
      provider.get_creds.should eq( {
        :access_key_id => (ENV['AWS_ACCESS_KEY_ID']||ENV['AWS_ACCESS_KEY']), 
        :secret_access_key => (ENV['AWS_SECRET_ACCESS_KEY']||ENV['AWS_SECRET_KEY'])
      })
    end
  end
end

