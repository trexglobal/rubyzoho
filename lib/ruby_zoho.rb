require 'zoho_api'
require 'api_utils'
require 'yaml'

module RubyZoho

  class Configuration
    attr_accessor :api, :api_key, :cache_fields, :crm_modules, :ignore_fields_with_bad_names

    def initialize
      self.api_key = nil
      self.api = nil
      self.cache_fields = false
      self.crm_modules = nil
      self.ignore_fields_with_bad_names = true
    end
  end

  class << self
    attr_accessor :configuration
  end

  def self.configure
    puts "Configuring RubyZoho..."
    self.configuration ||= Configuration.new
    yield(configuration) if block_given?
    self.configuration.crm_modules ||= []
    self.configuration.crm_modules = %w[Accounts Calls Contacts Events Leads Potentials Tasks].concat(
        self.configuration.crm_modules).uniq
    self.configuration.api = init_api(self.configuration.api_key,
                                      self.configuration.crm_modules, self.configuration.cache_fields)
    RubyZoho::Crm.setup_classes()
    puts "Configured RubyZoho"
  end

  def self.init_api(api_key, modules, cache_fields)
    base_path = File.join(File.dirname(__FILE__), '..', 'spec', 'fixtures')
    if File.exists?(File.join(base_path, 'fields.snapshot')) && cache_fields == true
      fields = YAML.load(File.read(File.join(base_path, 'fields.snapshot')))
      zoho = ZohoApi::Crm.new(api_key, modules,
                              self.configuration.ignore_fields_with_bad_names, fields)
    else
      zoho = ZohoApi::Crm.new(api_key, modules, self.configuration.ignore_fields_with_bad_names)
      fields = zoho.module_fields
      File.open(File.join(base_path, 'fields.snapshot'), 'wb') { |file| file.write(fields.to_yaml) } if cache_fields == true
    end
    zoho
  end

  require 'crm'

end
