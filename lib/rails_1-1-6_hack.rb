# I advertized that this plugin worked with EdgeRails or 1.1.6 with assert_select, but I had made some changes that required EdgeRails since I last tested with 1.1.6.  This is a backwards-compatibility hack.

module FormTestHelper
  class Form
    def submit_without_clicking_button
      path = self.action.blank? ? @testcase.instance_variable_get("@request").request_uri : self.action # If no action attribute on form, it submits to the same URI
      params = {}
      fields.each {|field| params[field.name] = field.value unless field.value.nil? || params[field.name] } # don't submit the nils and fields already named
      
      # Convert arrays and hashes in params, since test processing doesn't do this automatically
      # params = CGIMethods::FormEncodedPairParser.new(params).result
      params.each {|k, v| params[k] = [v] }
      params = CGIMethods.parse_request_parameters(params)
      
      @testcase.make_request(request_method, path, params)
    end
  end
  
  def make_request(method, path, params={})
    if self.kind_of?(ActionController::IntegrationTest)
      self.send(method, path, params.stringify_keys)
    else
      # Have to generate a new request and have it recognized to be backwards-compatible wih 1.1.6
      request = ActionController::TestRequest.new
      request.request_uri = path
      request.env['REQUEST_METHOD'] = method.to_s.upcase
      ActionController::Routing::Routes.recognize(request)
      new_params = request.parameters
      params.merge!(new_params)
      
      if params[:controller] && params[:controller] != current_controller = self.instance_eval("@controller").controller_name
        raise "Can't follow links outside of current controller (from #{current_controller} to #{params[:controller]})"
      end
      self.send(method, params.delete("action"), params.stringify_keys)
    end
  end
end