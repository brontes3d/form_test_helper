require File.join(File.dirname(__FILE__), "test_helper")

class IntegrationTest < ActionController::IntegrationTest

  def setup
    get "/test/rhtml", :content => <<-EOD
      <%= link_to "Index", { :action => "index" } %>
      <%= form_tag(:action => 'create') %>
        <%= text_field_tag 'username', 'jason' %>
        <%= submit_tag %>
      <% end_form_tag %>
    EOD
  end

  def test_select_form
    form = select_form
    assert_equal 'jason', form['username'].value
    form['username'] = 'brent'
    form.submit
    assert_response :success
    assert_equal 'brent', controller.params['username']
  end
  
  def test_select_link
    link = select_link 'Index'
    link.follow
    assert_response :success
    assert_action_name :index
  end
end
