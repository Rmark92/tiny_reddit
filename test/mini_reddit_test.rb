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
    FileUtils.touch "#{datastore_dir}/submissions.pstore"
    FileUtils.touch "#{datastore_dir}/users.pstore"
  end

  def teardown
    FileUtils.rm "#{datastore_dir}/submissions.pstore"
    FileUtils.rm "#{datastore_dir}/users.pstore"
  end

  def session
    last_request.env["rack.session"]
  end

  def set_user_permissions
    { "rack.session" => { user_name: "User" } }
  end

  def submit_post(post)
    load_submissions
    @posts << post
    update_submissions
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
    assert_match /Signed in/, last_response.body
  end

  def test_register_with_username_duplicate
    load_users
    @users << User.new('User', 'password')
    update_users

    post '/register', params = {user_id: 'User', password: 'password' }
    assert_equal 200, last_response.status
    assert_match /username is already taken/, last_response.body
  end

  def test_register_with_invalid_username_chars_error
    post '/register', params = { user_id: "<>!!!User<><>", password: 'password' }
    assert_equal 200, last_response.status
    assert_match /can only include alphanumeric characters and spaces/, last_response.body
  end

  def test_username_length_error
    post '/register', params = { user_id: "This is longer than 20 characters", password: 'password' }
    assert_equal 200, last_response.status
    assert_match /must be less than 20 characters long/, last_response.body
  end

  def test_register_blank_username_error
    post '/register', params = { user_id: '     ', password: 'password' }
    assert_equal 200, last_response.status
    assert_match /must include alphanumeric characters/, last_response.body
  end

  def test_register_without_password_error
    post '/register', params = { user_id: 'User', password: ' ' }
    assert_equal 200, last_response.status
    assert_match /Password must include non-space characters/, last_response.body
  end

  def test_signin_view
    get 'signin'
    assert_equal 200, last_response.status
    assert_match /Sign in/, last_response.body
  end

  def test_signin_user
    load_users
    @users << User.new('User', 'password')
    update_users

    post '/signin', params = {user_id: 'User', password: 'password' }
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_match /Welcome, User/, last_response.body
    assert_equal 'User', session[:user_name]
  end

  def test_incorrect_password
    load_users
    @users << User.new('User', 'password')
    update_users

    post '/signin', params = {user_id: 'User', password: 'another password' }
    assert_equal 200, last_response.status
    assert_match /Invalid password/, last_response.body
  end

  def test_incorrect_username
    load_users
    @users << User.new('User', 'password')
    update_users

    post '/signin', params = {user_id: 'Another User', password: 'password' }
    assert_equal 200, last_response.status
    assert_match /we don't recognize that username/, last_response.body
  end

  def test_post_submission_view
    get '/submit_post', {}, set_user_permissions

    assert_equal 200, last_response.status
    assert_match /Submit Post/, last_response.body
  end

  def test_submit_post
    post '/submit_post', params = { title: 'Real Reddit', link: 'https://www.reddit.com/' }, set_user_permissions
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_match /successfully submitted/, last_response.body
    assert_match /Real Reddit/, last_response.body
    assert_match /seconds? ago/, last_response.body
    assert_match /Submitted by User/, last_response.body
  end

  def test_post_invalid_link_error
    post '/submit_post', params = { title: 'Real Reddit', link: 'a link' }, set_user_permissions

    assert_equal 200, last_response.status
    assert_match /Link must be an http address/, last_response.body
    assert_match /Submit Post/, last_response.body
  end

  def test_post_title_length_error
    attempted_title = 'Real Reddit' * 100
    post '/submit_post', params = { title: attempted_title, link: 'https://www.reddit.com/' }, set_user_permissions

    assert_equal 200, last_response.status
    assert_match /Title length must be 100 characters or less/, last_response.body
    assert_match /Submit Post/, last_response.body
  end

  def test_post_empty_title_error
    post '/submit_post', params = { title: '', link: 'https://www.reddit.com/' }, set_user_permissions

    assert_equal 200, last_response.status
    assert_match /Must enter a title and link/, last_response.body
    assert_match /Submit Post/, last_response.body
  end

  def test_post_empty_link_error
    post '/submit_post', params = { title: 'Real Reddit', link: '' }, set_user_permissions

    assert_equal 200, last_response.status
    assert_match /Must enter a title and link/, last_response.body
    assert_match /Submit Post/, last_response.body
  end

  def test_escape_html_post_submission
    attempted_title = "<script>Something bad</script>"
    post '/submit_post', params = { title: attempted_title, link: 'https://www.reddit.com/' }, set_user_permissions

    assert_equal 302, last_response.status
    get last_response["Location"]
    refute_match /<script>Something bad<\/script>/, last_response.body
    assert_match /script.+Something bad.+script/, last_response.body
  end

  def test_view_post_comments
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'Some User', [])
    @posts << post
    update_submissions

    get "/#{post.id}/comments"
    assert_equal 200, last_response.status
    assert_match /Real Reddit/, last_response.body
    assert_match /Add a new comment:/, last_response.body
  end

  def test_submit_post_reply
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'Some User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/comments", params = { text: 'Haha' }, set_user_permissions

    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /Real Reddit/, last_response.body
    assert_match /Haha/, last_response.body
  end

  def test_delete_post
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/delete", {}, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /successfully deleted/, last_response.body
    refute_match /Real Reddit/, last_response.body
    refute_match /www.reddit.com/, last_response.body
    assert_match /class="post deleted"/, last_response.body

    load_submissions
    post = @posts.last
    assert post.deleted?
  end

  def test_delete_post_exclusive_to_submitter
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    get "/", {}, { "rack.session" => { user_name: 'Another User' } }
    assert_equal 200, last_response.status
    refute_match /Delete/, last_response.body

    get "/", {}, { "rack.session" => { user_name: 'User' } }
    assert_equal 200, last_response.status
    assert_match /Delete/, last_response.body
  end

  def test_comment_reply_view
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    post.add_reply('Haha', 'User')
    comment = post.replies.last
    @posts << post
    update_submissions

    get "#{post.id}/comments/#{comment.id}/reply", {}, set_user_permissions
    assert_equal 200, last_response.status
    assert_match /Reply:/, last_response.body
  end

  def test_reply_to_comment
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    post.add_reply('Haha', 'User')
    comment = post.replies.last
    @posts << post
    update_submissions

    post "/#{post.id}/comments/#{comment.id}/reply", params = { text: 'LOL' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /successfully submitted/, last_response.body
    assert_match /LOL/, last_response.body

    load_submissions
    post = @posts.last
    comment = post.replies.last
    assert comment.replies.any? { |comment| comment.text == "LOL" }
  end

  def test_delete_comment
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    post.add_reply('Haha', 'User')
    comment = post.replies.last
    @posts << post
    update_submissions

    post "/#{post.id}/comments/#{comment.id}/delete", {}, set_user_permissions
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_match /successfully deleted/, last_response.body
    assert_match /class="comment deleted"/, last_response.body
    refute_match /Haha/, last_response.body
  end

  def test_delete_comment_exclusive_to_submitter
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    post.add_reply('Haha', 'User')
    comment = post.replies.last
    @posts << post
    update_submissions

    get "/#{post.id}/comments", {}, { "rack.session" => { user_name: 'Another User' } }
    assert_equal 200, last_response.status
    refute_match /Delete/, last_response.body

    get "/#{post.id}/comments", {}, { "rack.session" => { user_name: 'User' } }
    assert_equal 200, last_response.status
    assert_match /Delete/, last_response.body
  end

  def test_upvote
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'upvote' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="upvote selected".+value="remove"/m, last_response.body
    assert_match /<div class="score">1<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal 1, post.score
  end

  def test_downvote
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'downvote' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="downvote selected".+value="remove"/m, last_response.body
    assert_match /<div class="score">-1<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal -1, post.score
  end

  def test_remove_vote
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'upvote' }, set_user_permissions
    post "/#{post.id}/vote", params = { choice: 'remove' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="upvote unselected"/, last_response.body
    assert_match /<div class="score">0<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal 0, post.score
  end

  def test_one_upvote_per_user
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'upvote' }, set_user_permissions
    post "/#{post.id}/vote", params = { choice: 'upvote' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="upvote selected"/, last_response.body
    assert_match /<div class="score">1<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal 1, post.score
  end

  def test_one_downvote_per_user
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'downvote' }, set_user_permissions
    post "/#{post.id}/vote", params = { choice: 'downvote' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="downvote selected"/, last_response.body
    assert_match /<div class="score">-1<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal -1, post.score
  end

  def test_switch_upvote_to_downvote
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'upvote' }, set_user_permissions
    post "/#{post.id}/vote", params = { choice: 'downvote' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="upvote unselected"/, last_response.body
    assert_match /class="downvote selected"/, last_response.body
    assert_match /<div class="score">-1<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal -1, post.score
  end

  def test_switch_downvote_to_upvote
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'downvote' }, set_user_permissions
    post "/#{post.id}/vote", params = { choice: 'upvote' }, set_user_permissions
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /class="upvote selected"/, last_response.body
    assert_match /class="downvote unselected"/, last_response.body
    assert_match /<div class="score">1<\/div>/, last_response.body

    load_submissions
    post = @posts.last
    assert_equal 1, post.score
  end

  def test_attempt_post_submission_logged_out
    get "/submit_post"
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /Must be signed in to perform this action/, last_response.body

    post "/submit_post", params = { text: 'Real Reddit', link: 'https://www.reddit.com' }
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /Must be signed in to perform this action/, last_response.body
  end

  def test_attempt_vote_logged_out
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/vote", params = { choice: 'upvote' }
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /Must be signed in to perform this action/, last_response.body
  end

  def test_attempt_post_reply_logged_out
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    @posts << post
    update_submissions

    post "/#{post.id}/comments", params = { text: 'Some Reply' }
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /Must be signed in to perform this action/, last_response.body
  end

  def test_attempt_comment_reply_logged_out
    load_submissions
    post = Post.new('Real Reddit', 'https://www.reddit.com/', 'User', [])
    post.add_reply('Haha', 'User')
    comment = post.replies.last
    @posts << post
    update_submissions

    post "/#{post.id}/comments/#{comment.id}/reply", params = { text: 'Some Reply' }
    assert_equal 302, last_response.status
    get last_response["Location"]
    assert_match /Must be signed in to perform this action/, last_response.body
  end

  def test_post_order
    load_submissions
    post1 = Post.new('First Post', 'https://www.reddit.com/', 'User', [])
    @posts << post1
    post2 = Post.new('Second Post', 'https://www.reddit.com/', 'User', [])
    post2.upvote('User')
    @posts << post2
    update_submissions

    get "/"
    assert_equal 200, last_response.status
    assert_match /Second Post.+First Post/m, last_response.body
  end

  def test_comment_order
    load_submissions
    post = Post.new('First Post', 'https://www.reddit.com/', 'User', [])
    post.add_reply('HAHA', 'User')
    post.add_reply('LOL', 'User')
    comment1 = post.replies.first
    comment2 = post.replies.last
    comment2.add_reply('lol', 'User')
    comment2_child = comment2.replies.last
    comment2.upvote('User')
    @posts << post
    update_submissions

    get "/#{post.id}/comments"
    assert_equal 200, last_response.status
    assert_match /LOL.+lol.+HAHA/m, last_response.body
  end
end
