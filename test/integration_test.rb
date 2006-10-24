require File.join(File.dirname(__FILE__), "test_helper")

class IntegrationTest < ActionController::IntegrationTest

  def setup
    get "/test/rhtml", :content => <<-EOD
      <%= link_to "Index", { :action => "index" } %>
      <%= link_to 'Destroy', { :action => 'destroy'}, :method => :delete %>
      <%= form_tag(:action => 'create', :method => :post) %>
        <%= text_field_tag 'username', 'jason' %>
        <%= submit_tag %>
      </form>
    EOD
  end

  def test_select_form
    form = select_form
    assert_equal 'jason', form['username'].value
    form['username'] = 'brent'
    form.submit
    assert_response :success
    assert request.post?
    assert_equal 'brent', controller.params['username']
  end
  
  def test_select_link
    link = select_link 'Index'
    link.follow
    assert_response :success
    assert_action_name :index
  end

  # FIXME: I think this is broken in EdgeRails.  A simple delete '/test/delete' raises "undefined method 'recycle!."  It has nothing to do with this plugin and hopefully will be fixed soon.
  # def test_click_link_with_different_method
  #   link = select_link "/test/destroy"
  #   link.follow
  #   assert_response :success
  #   assert_action_name :destroy
  # end
end
