require 'active_model'
require 'crud_methods'
require 'zoho_crm_utils'

class RubyZoho::Crm

  class << self
    attr_accessor :module_name
  end
  @module_name = 'Crm'

  include CrudMethods
  include ZohoCrmUtils

  def initialize(object_attribute_hash = {})
    @fields = object_attribute_hash == {} ? RubyZoho.configuration.api.fields(self.class.module_name) :
        object_attribute_hash.keys
    create_accessor(self.class, @fields)
    create_accessor(self.class, [:module_name])
    public_send(:module_name=, self.class.module_name)
    update_or_create_attrs(object_attribute_hash)
    self
  end

  def self.method_missing(meth, *args, &block)
    if meth.to_s =~ /^find_by_(.+)$/
      run_find_by_method($1, *args, &block)
    else
      super
    end
  end


  # 
  # Save multiple objects using single request
  # @param objects [Array] List of object to save
  # 
  # @return [Hash] Zoho return hash 
  def self.multi_save(objects)

    request_url = RubyZoho.configuration.api.create_url(self.module_name, 'insertRecords')
    
    request_document = REXML::Document.new
    module_element = request_document.add_element self.module_name

    groupped_by_url = {}

    objects.each_with_index do |object, row_id|

      fields_values_hash = {}
      object.fields.each { |f| fields_values_hash.merge!({ f => object.send(f) }) }
      fields_values_hash.delete_if { |k, v| v.nil? }

      row = module_element.add_element 'row', { 'no' => row_id+1 }
      fields_values_hash.each_pair { |k, v| RubyZoho.configuration.api.add_field(row, ApiUtils.symbol_to_string(k), v) }

    end

    request_result = RubyZoho.configuration.api.class.post(request_url, {
      :query => {
        :newFormat => 1,
        :authtoken => RubyZoho.configuration.api_key,
        :scope => 'crmapi', :xmlData => request_document
      },
      :headers => { 'Content-length' => '0'}
    })

    RubyZoho.configuration.api.check_for_errors(request_result)
    x_r = REXML::Document.new(request_result.body).elements.to_a('//recorddetail')
    
    return RubyZoho.configuration.api.to_hash(x_r, module_name)[0]
  end

  #
  # batch insert objects using single request
  # @param objects [Array] List of object to save
  #
  # @return [Hash] status
  def self.batch_insert(objects, wfTrigger=false, verbose=false)
    request_url = RubyZoho.configuration.api.create_url(self.module_name, 'insertRecords')

    request_document = REXML::Document.new
    module_element = request_document.add_element self.module_name
    objects.each_with_index do |object, index|
      fields_values_hash = {}
      object.fields.each { |f| fields_values_hash.merge!({ f => object.send(f) }) }
      fields_values_hash.delete_if { |k, v| v.nil? }

      row = module_element.add_element('row', { 'no' => index+1 })
      fields_values_hash.each_pair { |k, v| RubyZoho.configuration.api.add_field(row, ApiUtils.symbol_to_string(k), v) }
      puts "insert_field_values=#{fields_values_hash.to_json}" if verbose
    end

    puts "request_document=#{request_document}" if verbose
    request_result = RubyZoho.configuration.api.class.post(request_url, {
      :query => {
        :wfTrigger=>wfTrigger,
        :newFormat=>1,
        :version=>4,
        :authtoken => RubyZoho.configuration.api_key,
        :scope => 'crmapi', :xmlData => request_document
      },
      :headers => { 'Content-length' => '0'}
    })
    unless request_result.code == 200
      return {success: false, error_code: 'WEB_SERVICE_CALL_FAILED', error_message: "Web service call failed with #{request_result.code}", request_result:request_result}
    end
    puts "ws_request_result=#{request_result}" if verbose
    begin
      request_result_by_row = build_batch_request_result(objects, request_result, verbose)
      return {success:true, request_result: request_result_by_row}
    rescue => e
      puts e.inspect
      puts e.backtrace.join("\n")
      return {success: false, error_code: 'INVALID_REQUEST_RESULT', error_message: "Web service call returned invalid/malformed request result", request_result:request_result}
    end
  end

  #
  # batch update objects using single request
  # @param objects [Array] List of objects to update. Each object must have :id field value
  #
  # @return [Hash] status
  def self.batch_update(objects, wfTrigger=false, verbose=false)
    request_url = RubyZoho.configuration.api.create_url(self.module_name, 'updateRecords')
    request_document = REXML::Document.new
    module_element = request_document.add_element self.module_name
    invalid_objects = []
    objects.each_with_index do |object, index|
      fields_values_hash = {}
      object.fields.each { |f| fields_values_hash.merge!({ f => object.send(f) })}
      fields_values_hash.delete_if { |k, v| v.nil? }
      puts "update_field_values=#{fields_values_hash.to_json}" if verbose
      id = fields_values_hash[:id]
      if id
        puts "id=#{id}" if verbose
        fields_values_hash.delete(:id)
        row = module_element.add_element 'row', { 'no' => index+1 }
        RubyZoho.configuration.api.add_id_field(row, id)
        fields_values_hash.each_pair { |k, v| RubyZoho.configuration.api.add_field(row, ApiUtils.symbol_to_string(k), v) }
      else
        invalid_objects << {:error_message => 'id not found',  :error_object =>object}
      end
    end
    unless invalid_objects.empty?
      return {success: false, error_code: 'INVALID_REQUEST_OBJECT', error_message: "Invalid request object(s)", invalid_objects: invalid_objects}
    end
    puts "request_document=#{request_document}" if verbose
    #return {success: true, request_result: {}}  # keep this for debug
    # :version=>4 is required to execute in batch mode
    request_result = RubyZoho.configuration.api.class.post(request_url, {
      :query => {
        :wfTrigger=>wfTrigger,
        :version=>4,
        :authtoken => RubyZoho.configuration.api_key,
        :scope => 'crmapi', :xmlData => request_document
      },
      :headers => { 'Content-length' => '0'}
    })

    unless request_result.code == 200
      return {success: false, error_code: 'WEB_SERVICE_CALL_FAILED', error_message: "Web service call failed with #{request_result.code}", request_result:request_result}
    end
    puts "ws_request_result=#{request_result}" if verbose
    begin
      request_result_by_row = build_batch_request_result(objects, request_result, verbose)
      return {success:true, request_result: request_result_by_row}
    rescue => e
      puts e.inspect
      puts e.backtrace.join("\n")
      return {success: false, error_code: 'INVALID_REQUEST_RESULT', error_message: "Web service call returned invalid/malformed request result", request_result:request_result}
    end
  end

  def self.build_batch_request_result(objects, request_result, verbose=false)
    result_by_row = {}
    REXML::Document.new(request_result.body).elements.to_a('//response/result/row').each do |row|
      row_no = row.attribute('no').value
      row_result = row.elements.first #only one element expected either 'success' or 'error'
      unless row_result
        result_by_row[row_no] = {row: row_no, success: false, message: 'Malformed request result', id: nil}
        next
      end

      code = safe_xml_element_text_value(row_result.elements['code'])
      status = row_result.name
      if status == 'success'
        id = safe_xml_element_text_value(row_result.elements["details/FL[@val='Id']"])
        if id
          success = true
          message = ''
        else
          success = false
          message = 'Request processed successfully, but Id not found in request result'
        end
      elsif status =='error'
        id = nil
        success = false
        message = safe_xml_element_text_value(row_result.elements['details'])
      else
        id = nil
        success = false
        message = 'Unknown request result status'
      end
      result_by_row[row_no] = {row: row_no, success: success, code: code, message: message, id: id}
    end
    objects.each_with_index do |object, index|
      row_no = index + 1
      result = result_by_row[row_no.to_s]
      unless result
        message = "No request result found for #{row_no}"
        puts message if verbose
        result = result_by_row[row_no.to_s] = {row: row_no, success: false, code: nil, message: message, id: nil}
      end
      result[:source_object] = object
    end
    puts "result_by_row=#{result_by_row}" if verbose
    return result_by_row
  end

  def self.safe_xml_element_text_value(element)
    return nil unless element
    return element.text
  end

  def method_missing(meth, *args, &block)
    if [:seid=, :semodule=].index(meth)
      run_create_accessor(self.class, meth)
      self.send(meth, args[0])
    else
      super
    end
  end

  def self.run_find_by_method(attrs, *args, &block)
    attrs = attrs.split('_and_')
    conditions = Array.new(args.size, '=')
    h = RubyZoho.configuration.api.find_records(
        self.module_name, ApiUtils.string_to_symbol(attrs[0]), conditions[0], args[0]
    )
    return h.collect { |r| new(r) } unless h.nil?
    nil
  end

  def << object
    object.semodule = self.module_name
    object.seid = self.id
    object.fields << :seid
    object.fields << :semodule
    save_object(object)
  end

  def primary_key
    RubyZoho.configuration.api.primary_key(self.class.module_name)
  end

  def self.setup_classes
    RubyZoho.configuration.crm_modules.each do |module_name|
      klass_name = module_name.chop
      c = Class.new(self) do
        include RubyZoho
        include ActiveModel
        extend ActiveModel::Naming

        attr_reader :fields
        @module_name = module_name
      end
      const_set(klass_name, c)
    end
  end

  c = Class.new(self) do
    def initialize(object_attribute_hash = {})
      module_name = 'Users'
      super
    end

    def self.delete(id)
      raise 'Cannot delete users through API'
    end

    def save
      raise 'Cannot delete users through API'
    end

    def self.all
      result = RubyZoho.configuration.api.users('AllUsers')
      result.collect { |r| new(r) }
    end

    def self.find_by_email(email)
      r = []
      self.all.index { |u| r << u if u.email == email }
      r
    end

    def self.method_missing(meth, *args, &block)
      Crm.module_name = 'Users'
      super
    end
  end

  Kernel.const_set 'CRMUser', c

end
