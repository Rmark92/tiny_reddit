ENV["RACK_ENV"] = "development"

require 'minitest/autorun'
require 'rack/test'
require 'fileutils'

require_relative '../application'

class MiniRedditTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(datastore_dir)
  end

  def teardown
    FileUtils.rm_rf(datastore_dir)
  end

  def session
    last_request.env["rack.session"]
  end

  def set_user_permissions
    { "rack.session" => { user_name: "User" } }
  end

  def create_post(title, link)
    submission_store = PStore.new("#{datastore_dir}/submissions.pstore")
    posts = submission_store.transaction { submission_store[:posts] } || []
    used_ids = posts.map(&:id)
    posts << Post.new(title, link, user_name, used_ids)
    submission_store.transaction { submission_store[:posts] = posts }
  end

  def test_home_page
    get '/'
    assert_equal 200, last_response.status
    assert_match /Tiny Reddit/, last_response.body
  end

  def test_register_view
    get '/register'
    assert_equal 200, last_response.status
    assert_match /Register/, last_response.body
  end

  def test_register_new_user
    post '/register', params = { user_id: 'Ryan', password: 'password' }

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_match /Thanks for registering/, last_response.body
  end

  def test_
end
