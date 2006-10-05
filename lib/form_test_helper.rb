module FormTestHelper
  module TagProxy
    def method_missing(method, *args)
      if tag.respond_to?(method)
        tag.send(method, *args)
      else
        super
      end
    end
  end
  
  class Form
    class FieldNotFoundError < RuntimeError; end
    class MissingSubmitError < RuntimeError; end
    include TagProxy
    attr_reader :tag
    
    def initialize(tag, testcase)
      @tag, @testcase = tag, testcase
    end
    
    # If you submit the form with JavaScript
    def submit_without_clicking_button
      path = self.action.blank? ? @testcase.instance_variable_get("@request").request_uri : self.action # If no action attribute on form, it submits to the same URI
      params = {}
      fields.each {|field| params[field.name] = field.value unless field.value.nil? || params[field.name] } # don't submit the nils and fields already named
      
      @testcase.make_request(request_method, path, params)
    end
    
    # Submits the form.  Raises an exception if no submit button is present.
    def submit(opts={})
      raise MissingSubmitError, "Submit button not found!" unless self.fields.any? {|field| field.is_a?(Submit) }
      opts.stringify_keys.each do |key, value|
        self[key] = value
      end
      submit_without_clicking_button
    end
    
    def field_names
      fields.collect {|field| field.name }
    end
    
    def fields
      # Input, textarea, select, and button are valid field tags.  Name is a required attribute.
      @fields ||= tag.select('input, textarea, select, button').reject {|field_tag| field_tag['name'].nil? }.group_by {|field_tag| field_tag['name'] }.collect do |name, field_tags|
        case field_tags.first['type']
        when 'submit'
          FormTestHelper::Submit.new(self, field_tags)
        when 'checkbox'
          FormTestHelper::CheckBox.new(self, field_tags)
        when 'hidden'
          FormTestHelper::Hidden.new(self, field_tags)
        when 'radio'
          FormTestHelper::RadioButtonGroup.new(self, field_tags)
        else
          if field_tags.first.name == 'select'
            FormTestHelper::Select.new(self, field_tags)
          else
            FormTestHelper::Field.new(self, field_tags)
          end
        end
      end
    end
    
    def find_field_by_name(field_name)
      matching_fields = self.fields.select {|field| field.name == field_name.to_s }
      return nil if matching_fields.empty?
      matching_fields.first
    end
    
    # Same as find_field_by_name but raises an exception if the field doesn't exist.
    def [](field_name)
      find_field_by_name(field_name) || raise(FieldNotFoundError, "Field named #{field_name} not found in form.")
    end
    
    def []=(field_name, value)
      self[field_name].value = value
    end
    
    def reset
      fields.each {|field| field.reset }
    end
    
    def action
      tag["action"]
    end
    
    def request_method
      hidden_method_field = self.find_field_by_name("_method")
      if hidden_method_field # PUT and DELETE
        hidden_method_field.value.to_sym
      elsif tag["method"] && !tag["method"].blank? # POST and GET
        tag["method"].to_sym
      else # No method specified in form tags
        :get
      end
    end
  end
  
  class Field
    include TagProxy
    attr_accessor :value
    attr_reader :name, :tags
    
    def initialize(form, tags)
      @form, @tags = form, tags
      reset
    end
        
    def tag
      tags.first
    end
    
    def initial_value
      if tag['value']
        tag['value']
      elsif tag.children
        tag.children.to_s
      end
    end
    
    def name
      tag['name']
    end
    
    def reset
      @value = initial_value
    end
  end
  
  class Submit < Field; end
  
  class CheckBox < Field
    def initial_value
      tag['checked'] ? checked_value : unchecked_value
    end
    
    def checked_value
      @checkbox_tag = tags.detect {|field_tag| field_tag['type'] == 'checkbox' }
      @checkbox_tag['value']
    end
    
    def unchecked_value
      @hidden_tag = tags.detect {|field_tag| field_tag['type'] == 'hidden' }
      @hidden_tag ? @hidden_tag['value'] : nil
    end
    
    def value=(value)
      case value
      when TrueClass, FalseClass
        @value = value ? checked_value : unchecked_value
      when checked_value, unchecked_value
        super
      else
        raise "Checkbox value must be one of #{[checked_value, unchecked_value].inspect}."
      end
    end
    
    def check
      self.value = checked_value
    end
    
    def uncheck
      self.value = unchecked_value
    end
  end
  
  class RadioButtonGroup < Field
    def initial_value
      checked_tags = tags.select {|tag| tag['checked'] }
      # If multiple radio buttons are checked, Firefox uses the last one
      # If none, the value is undefined and is not submitted
      checked_tags.any? ? checked_tags.last['value'] : nil
    end
    
    def options
      tags.collect {|tag| tag['value'] }
    end
  end
  
  class Select < Field
    def initialize(form, tags)
      @options = tags.first.select("option").collect {|option_tag| Option.new(self, option_tag) }
      super
    end
    
    def initial_value
      selected_options = @options.select(&:initially_selected)
      case selected_options.size
      when 1
        selected_options.first.value
      when 0 # If no option is selected, browsers generally use the first
        options.first
      else
        if tag['multiple']
          selected_options.collect(&:value)
        else # When multiple options selected but the attr not specified, Firefox selects the last
          selected_options.last.value 
        end
      end
    end
    
    def options
      if options_are_labeled?
        @options.collect do |option|
          [option.label, option.value]
        end
      else
        @options.collect(&:value)
      end
    end
    
    def options_are_labeled?
      @options.any? {|option| option.label }
    end
    
    def value=(value)
      if options.include?(value)
        @value = value
      elsif options_are_labeled? && pair = options.assoc(value) # Value set by label
        @value = pair.last
      else
        raise "Can't set value for <select> that isn't an <option>."
      end
    end
  end
  
  class Option
    attr_reader :tag, :label, :value, :initially_selected
    def initialize(select, tag)
      @select, @tag = select, tag
      @initially_selected = tag['selected']
      content = tag.children.to_s
      value = tag['value']
      if value && value != content # Like <option value="7">United States</option>
        @label = content
        @value = value
      else # Label is nil if like <option>United States</option> or value == content
        @value = content
      end
    end
  end
  
  class Hidden < Field
    def value=(value)
      raise TypeError, "Can't modify hidden field's value"
    end
    
    # Permit changing the value of a hidden field (as if using Javascript)
    def set_value(value)
      @value = value
    end
  end
  
  def select_link(text=nil)
    if css_select(%Q{a[href="#{text}"]}).any?
      links = assert_select("a[href=?]", text)
    elsif text.nil?
      links = assert_select('a', 1)
    else
      links = assert_select('a', text)
    end
    decorate_link(links.first)
  end
  
  def decorate_link(link)
    link.extend FormTestHelper::Link
    link.testcase = self
    link
  end
  
  def select_form(text=nil)
    forms = case
    when text.nil?
      assert_select("form", 1)
    when css_select(%Q{form[action="#{text}"]}).any?
      assert_select("form[action=?]", text)
    else
      assert_select('form#?', text)
    end
    Form.new(forms.first, self)
  end
  
  module Link
    def follow
      path = self.href
      @testcase.make_request(request_method, path)
    end
    alias_method :click, :follow
    
    def href
      self["href"]
    end
    
    def request_method
      if self["onclick"] && self["onclick"] =~ /'_method'.*'value', '(\w+)'/
        $1.to_sym
      else
        :get
      end
    end
    
    def testcase=(testcase)
      @testcase = testcase
      self
    end
  end
  
  def make_request(method, path, params={})
    if self.kind_of?(ActionController::IntegrationTest)
      self.send(method, path, params.stringify_keys)
    else
      params.merge!(ActionController::Routing::Routes.recognize_path(path, :method => method))
      if params[:controller] && params[:controller] != current_controller = self.instance_eval("@controller").controller_name
        raise "Can't follow links outside of current controller (from #{current_controller} to #{params[:controller]})"
      end
      self.send(method, params.delete(:action), params.stringify_keys)
    end
  end
end