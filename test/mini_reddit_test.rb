ENV["RACK_ENV"] = "development"

require 'minitest/autorun'
require 'rack/test'

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
    last_request.env['rack.session']
  end

  def set_user_permissions(username)
    { 'rack.session' => { user_name: username } }
  end

  def create_new_post(title, link, username)
    posts = load_submissions_store
    used_ids = posts.map(&:id)
    new_post = Post.new(title, link, username, used_ids)
    yield(new_post) if block_given?
    posts << new_post
    update_submissions_store(posts)
    new_post
  end

  def create_new_user(user_name, password)
    users = load_users_store
    new_user = User.new(user_name, password)
    users << new_user
    update_users_store(users)
    new_user
  end

  def test_home_page
    get '/'
    assert_equal 200, last_response.status
    assert_match(/Tiny Reddit/, last_response.body)
  end

  def test_register_view
    get '/register'
    assert_equal 200, last_response.status
    assert_match(/Register/, last_response.body)
  end

  def test_register_new_user
    post '/register', { user_id: 'Ryan', password: 'password' }

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_match(/Thanks for registering/, last_response.body)
    assert_match(/Signed in/, last_response.body)
  end

  def test_register_with_username_duplicate
    create_new_user('User', 'password')

    post '/register', {user_id: 'User', password: 'password' }
    assert_equal 200, last_response.status
    assert_match(/username is already taken/, last_response.body)
  end

  def test_register_with_invalid_username_chars_error
    post '/register', { user_id: "<>!!!User<><>", password: 'password' }
    assert_equal 200, last_response.status
    assert_match(/can only include alphanumeric characters and spaces/, last_response.body)
  end

  def test_username_length_error
    post '/register', { user_id: "This is longer than 20 characters", password: 'password' }
    assert_equal 200, last_response.status
    assert_match(/must be less than 20 characters long/, last_response.body)
  end

  def test_register_blank_username_error
    post '/register', { user_id: '     ', password: 'password' }
    assert_equal 200, last_response.status
    assert_match(/must include alphanumeric characters/, last_response.body)
  end

  def test_register_without_password_error
    post '/register', { user_id: 'User', password: ' ' }
    assert_equal 200, last_response.status
    assert_match(/Password must include non-space characters/, last_response.body)
  end

  def test_signin_view
    get 'signin'
    assert_equal 200, last_response.status
    assert_match(/Sign in/, last_response.body)
  end

  def test_signin_user
    create_new_user('User', 'password')

    post '/signin', {user_id: 'User', password: 'password' }
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_match(/Welcome, User/, last_response.body)
    assert_equal 'User', session[:user_name]
  end

  def test_incorrect_password
    create_new_user('User', 'password')

    post '/signin', {user_id: 'User', password: 'another password' }
    assert_equal 200, last_response.status
    assert_match(/Invalid password/, last_response.body)
  end

  def test_incorrect_username
    create_new_user('User', 'password')

    post '/signin', {user_id: 'Another User', password: 'password' }
    assert_equal 200, last_response.status
    assert_match(/we don't recognize that username/, last_response.body)
  end

  def test_signout
    create_new_user('User', 'password')

    post '/signout', {}, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_equal 200, last_response.status
    assert_match(/Successfully signed out/, last_response.body)
 end


  def test_post_submission_view
    get '/submit_post', {}, set_user_permissions('User')

    assert_equal 200, last_response.status
    assert_match(/Submit Post/, last_response.body)
  end

  def test_submit_post
    post '/submit_post', { title: 'Real Reddit', link: 'https://www.reddit.com/' }, set_user_permissions('User')
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_match(/successfully submitted/, last_response.body)
    assert_match(/Real Reddit/, last_response.body)
    assert_match(/seconds? ago/, last_response.body)
    assert_match(/Submitted by User/, last_response.body)
  end

  def test_post_invalid_link_error
    post '/submit_post', { title: 'Real Reddit', link: 'a link' }, set_user_permissions('User')

    assert_equal 200, last_response.status
    assert_match(/Link must be an http address/, last_response.body)
    assert_match(/Submit Post/, last_response.body)
  end

  def test_post_title_length_error
    attempted_title = 'Real Reddit' * 100
    post '/submit_post', { title: attempted_title, link: 'https://www.reddit.com/' }, set_user_permissions('User')

    assert_equal 200, last_response.status
    assert_match(/Title length must be 100 characters or less/, last_response.body)
    assert_match(/Submit Post/, last_response.body)
  end

  def test_post_empty_title_error
    post '/submit_post', { title: '', link: 'https://www.reddit.com/' }, set_user_permissions('User')

    assert_equal 200, last_response.status
    assert_match(/Must enter a title and link/, last_response.body)
    assert_match(/Submit Post/, last_response.body)
  end

  def test_post_empty_link_error
    post '/submit_post', { title: 'Real Reddit', link: '' }, set_user_permissions('User')

    assert_equal 200, last_response.status
    assert_match(/Must enter a title and link/, last_response.body)
    assert_match(/Submit Post/, last_response.body)
  end

  def test_escape_html_post_submission
    attempted_title = "<script>Something bad</script>"
    post '/submit_post', { title: attempted_title, link: 'https://www.reddit.com/' }, set_user_permissions('User')

    assert_equal 302, last_response.status
    get last_response['Location']
    refute_match(/<script>Something bad<\/script>/, last_response.body)
    assert_match(/script.+Something bad.+script/, last_response.body)
  end

  def test_view_post_comments
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    get "/#{post.id}/comments"
    assert_equal 200, last_response.status
    assert_match(/Real Reddit/, last_response.body)
    assert_match(/Add a new comment:/, last_response.body)
  end

  def test_submit_post_reply
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/comments", { text: 'Haha' }, set_user_permissions('User')

    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/Comment successfully posted/, last_response.body)
    assert_match(/Real Reddit/, last_response.body)
    assert_match(/Haha/, last_response.body)
  end

  def test_delete_post
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    get "/", {}, set_user_permissions('User')
    assert_equal 200, last_response.status
    assert_match(/Delete/, last_response.body)

    post "/#{post.id}/delete", {}, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/successfully deleted/, last_response.body)
    refute_match(/Real Reddit/, last_response.body)
    assert_match(/class="post deleted"/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert post.deleted?
  end

  def test_delete_post_exclusive_to_submitter
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    get "/", {}, set_user_permissions('Another User')
    assert_equal 200, last_response.status
    refute_match(/Delete/, last_response.body)

    post "#{post.id}/delete", {}, set_user_permissions('Another User')
    assert_equal 302, last_response.status
    assert_match(/Posts can only be deleted by the user that submitted them/, session[:error])
    get last_response['Location'], {}, { 'rack.session' => session }
    assert_equal 200, last_response.status
    assert_match(/Posts can only be deleted by the user that submitted them/, last_response.body)
  end

  def test_comment_reply_view
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User') do |new_post|
             new_post.add_reply('Haha', 'User')
           end
    comment = post.replies.last

    get "#{post.id}/comments/#{comment.id}/reply", {}, set_user_permissions('User')
    assert_equal 200, last_response.status
    assert_match(/Reply:/, last_response.body)
  end

  def test_reply_to_comment
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User') do |new_post|
             new_post.add_reply('Haha', 'User')
           end
    comment = post.replies.last

    post "/#{post.id}/comments/#{comment.id}/reply", { text: 'LOL' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/successfully submitted/, last_response.body)
    assert_match(/LOL/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    comment = post.replies.last
    assert comment.replies.any? { |comment| comment.text == "LOL" }
  end

  def test_delete_comment
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User') do |new_post|
             new_post.add_reply('Haha', 'User')
           end
    comment = post.replies.last

    get "/#{post.id}/comments", {}, set_user_permissions('User')
    assert_equal 200, last_response.status
    assert_match(/Delete/, last_response.body)

    post "/#{post.id}/comments/#{comment.id}/delete", {}, set_user_permissions('User')
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_match(/successfully deleted/, last_response.body)
    assert_match(/class="comment deleted"/, last_response.body)
    refute_match(/Haha/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    comment = post.replies.last
    assert comment.deleted?
  end

  def test_delete_comment_exclusive_to_submitter
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User') do |new_post|
             new_post.add_reply('Haha', 'User')
           end
    comment = post.replies.last

    get "/#{post.id}/comments", {}, set_user_permissions('Another User')
    assert_equal 200, last_response.status
    refute_match(/Delete/, last_response.body)

    post "#{post.id}/comments/#{comment.id}/delete", {}, set_user_permissions('Another User')
    assert_equal 302, last_response.status
    get last_response['Location'], {}, { 'rack.session' => session }
    assert_match(/Only the user that submitted the comment can delete it/, last_response.body)
  end

  def test_upvote
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'upvote' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="upvote selected".+value="remove"/m, last_response.body)
    assert_match(/<div class="score">1<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal 1, post.score
  end

  def test_downvote
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'downvote' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="downvote selected".+value="remove"/m, last_response.body)
    assert_match(/<div class="score">-1<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal(-1, post.score)
  end

  def test_remove_vote
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'upvote' }, set_user_permissions('User')
    post "/#{post.id}/vote", { choice: 'remove' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="upvote unselected"/, last_response.body)
    assert_match(/<div class="score">0<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal 0, post.score
  end

  def test_one_upvote_per_user
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'upvote' }, set_user_permissions('User')
    post "/#{post.id}/vote", { choice: 'upvote' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="upvote selected"/, last_response.body)
    assert_match(/<div class="score">1<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal 1, post.score
  end

  def test_one_downvote_per_user
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'downvote' }, set_user_permissions('User')
    post "/#{post.id}/vote", { choice: 'downvote' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="downvote selected"/, last_response.body)
    assert_match(/<div class="score">-1<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal(-1, post.score)
  end

  def test_switch_upvote_to_downvote
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'upvote' }, set_user_permissions('User')
    post "/#{post.id}/vote", { choice: 'downvote' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="upvote unselected"/, last_response.body)
    assert_match(/class="downvote selected"/, last_response.body)
    assert_match(/<div class="score">-1<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal(-1, post.score)
  end

  def test_switch_downvote_to_upvote
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'downvote' }, set_user_permissions('User')
    post "/#{post.id}/vote", { choice: 'upvote' }, set_user_permissions('User')
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/class="upvote selected"/, last_response.body)
    assert_match(/class="downvote unselected"/, last_response.body)
    assert_match(/<div class="score">1<\/div>/, last_response.body)

    posts = load_submissions_store
    post = posts.last
    assert_equal 1, post.score
  end

  def test_attempt_post_submission_logged_out
    get "/submit_post"
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/Must be signed in to perform this action/, last_response.body)

    post "/submit_post", { text: 'Real Reddit', link: 'https://www.reddit.com' }
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/Must be signed in to perform this action/, last_response.body)
  end

  def test_attempt_vote_logged_out
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/vote", { choice: 'upvote' }
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/Must be signed in to perform this action/, last_response.body)
  end

  def test_attempt_post_reply_logged_out
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    post "/#{post.id}/comments", { text: 'Some Reply' }
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/Must be signed in to perform this action/, last_response.body)
  end

  def test_attempt_comment_reply_logged_out
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User') do |new_post|
             new_post.add_reply('Haha', 'User')
           end
    comment = post.replies.last

    post "/#{post.id}/comments/#{comment.id}/reply", { text: 'Some Reply' }
    assert_equal 302, last_response.status
    get last_response['Location']
    assert_match(/Must be signed in to perform this action/, last_response.body)
  end

  def test_post_order
    post1 = create_new_post('First Post', 'https://www.reddit.com/', 'User')
    post2 = create_new_post('Second Post', 'https://www.reddit.com/', 'User') do |new_post|
              new_post.upvote('User')
            end

    get "/"
    assert_equal 200, last_response.status
    assert_match(/Second Post.+First Post/m, last_response.body)
  end

  def test_comment_order
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User') do |new_post|
             new_post.add_reply('FIRST', 'User')
             new_post.add_reply('SECOND', 'User')
             parent = new_post.replies.last
             parent.add_reply('second', 'User')
           end

    get "/#{post.id}/comments"
    assert_equal 200, last_response.status
    assert_match(/SECOND.+second.+FIRST/m, last_response.body)
  end

  def test_view_invalid_post
    get "/fma452/comments"
    assert_equal 302, last_response.status
    assert_match(/Sorry, that post doesn't exist/, session[:error])
    get last_response['Location']
    assert_equal 200, last_response.status
    assert_match(/Sorry, that post doesn't exist/, last_response.body)
  end

  def test_reply_to_invalid_comment
    post = create_new_post('Real Reddit', 'https://www.reddit.com/', 'User')

    get "#{post.id}/comments/523532/reply", {}, set_user_permissions('User')
    assert_equal 302, last_response.status
    assert_match(/Sorry, that comment doesn't exist/, session[:error])
    get last_response['Location'], {}, { 'rack.session' => session }
    assert_match(/Sorry, that comment doesn't exist/, last_response.body)
  end
end
