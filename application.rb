require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'pry'
require 'pstore'
require 'fileutils'
require 'bcrypt'
require 'aws-sdk'
require_relative 'submission'
require_relative 'user'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

set(:auth) do |_|
  condition do
    unless session[:user_name]
      if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
        halt 401
      else
        session[:error] = 'Must be signed in to perform this action'
        redirect env['HTTP_REFERER']
      end
    end
  end
end

def datastore_dir
  if ENV['RACK_ENV'] == 'production'
    "#{File.dirname(__FILE__)}/data"
  else
    "#{File.dirname(__FILE__)}/test/data"
  end
end

def load_from_s3(file_name)
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  File.open("#{datastore_dir}/#{file_name}.pstore", 'w+') do |file|
    s3_client.get_object({ bucket: 'miniredditapp',
                           key: "#{file_name}_pstore.txt" },
                         target: file)
  end
end

def write_to_s3(file_name)
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  s3_client.put_object(bucket: 'miniredditapp',
                       body: File.read("#{datastore_dir}/#{file_name}.pstore"),
                       key: "#{filename}_pstore.txt")
end

def load_submissions_store
  load_from_s3('submissions') if ENV['RACK_ENV'] == 'production'
  submission_store = PStore.new("#{datastore_dir}/submissions.pstore")
  submission_store.transaction { submission_store[:posts] } || []
end

def update_submissions_store(posts)
  submission_store = PStore.new("#{datastore_dir}/submissions.pstore")
  submission_store.transaction { submission_store[:posts] = posts }
  write_to_s3('submissions') if ENV['RACK_ENV'] == 'production'
end

def load_users_store
  load_from_s3('users') if ENV['RACK_ENV'] == 'production'
  users_store = PStore.new("#{datastore_dir}/users.pstore")
  users_store.transaction { users_store[:users] } || []
end

def update_users_store(users)
  users_store = PStore.new("#{datastore_dir}/users.pstore")
  users_store.transaction { users_store[:users] = users }
  write_to_s3('users') if ENV['RACK_ENV'] == 'production'
end

helpers do
  def sort_submissions(submissions)
    submissions.sort_by(&:score).reverse
  end

  def list_comments(comments, indent = 0, &block)
    sort_submissions(comments).each do |comment|
      yield(comment, indent)
      list_comments(comment.replies, indent + 20, &block) if comment.replies
    end
  end

  def upvote_status(submission)
    submission.upvoted?(session[:user_name]) ? 'selected' : 'unselected'
  end

  def downvote_status(submission)
    submission.downvoted?(session[:user_name]) ? 'selected' : 'unselected'
  end
end

get '/' do
  @posts = load_submissions_store
  erb :home
end

get '/submit_post', auth: true do
  erb :submit_post
end

get '/register' do
  session[:original_referer] = env['HTTP_REFERER']
  erb :register
end

def new_username_error(username, taken_usernames)
  if username.nil? || username.empty?
    'Must enter something for your username'
  elsif username.strip.empty?
    'Username must include alphanumeric characters'
  elsif username.strip.size > 20
    'Username must be less than 20 characters long'
  elsif username =~ /[^\w\s]/
    'Username can only include alphanumeric characters and spaces'
  elsif taken_usernames.include?(username.strip)
    'Sorry, that username is already taken'
  end
end

def new_password_error(password)
  if password.nil?
    'Must enter something for your password'
  elsif password.strip.empty?
    'Password must include non-space characters'
  end
end

post '/register' do
  user_name = params[:user_id]
  password = params[:password]
  users = load_users_store
  taken_usernames = users.map(&:name)

  error_message = new_username_error(user_name, taken_usernames) ||
                  new_password_error(password)
  if error_message
    session[:error] = error_message
    erb :register
  else
    current_user = User.new(user_name.strip, password)
    users << current_user
    update_users_store(users)

    session[:user_name] = current_user.name
    session[:success] = "Thanks for registering, #{session[:user_name]}"
    redirect session[:original_referer] || '/'
  end
end

get '/signin' do
  session[:original_referer] = env["HTTP_REFERER"]
  erb :signin
end

def signin_attempt_error(username, password, users)
  attempted_user = users.detect { |user| user.name == username }

  if attempted_user.nil?
    "Sorry, we don't recognize that username"
  elsif password.nil?
    'Must enter a password'
  elsif !attempted_user.correct_password?(password)
    'Invalid password.  Please try again'
  else
    nil
  end
end

post '/signin' do
  username = params[:user_id]
  password = params[:password]
  users = load_users_store

  signin_error_message = signin_attempt_error(username, password, users)

  if signin_error_message
    session[:error] = signin_error_message
    erb :signin
  else
    session[:user_name] = username
    session[:success] = "Welcome, #{session[:user_name]}"
    redirect session[:original_referer] || '/'
  end
end

post '/signout' do
  session.delete(:user_name)
  session[:success] = 'Successfully signed out'
  redirect env['HTTP_REFERER']
end

def post_submission_error(title, link)
  if title.strip.empty? || link.strip.empty?
    'Must enter a title and link'
  elsif title.size > 100
    'Title length must be 100 characters or less'
  elsif link[0..3] != 'http'
    'Link must be an http address'
  end
end

post '/submit_post', auth: true do
  title = params[:title]
  link = params[:link]

  submission_error = post_submission_error(title, link)

  if submission_error
    session[:error] = submission_error
    erb :submit_post
  else
    posts = load_submissions_store
    used_ids = posts.map(&:id)
    new_post = Post.new(title, link, session[:user_name], used_ids)
    posts << new_post
    update_submissions_store(posts)
    session[:success] = 'Post successfully submitted!'
    redirect '/'
  end
end

def redirect_if_invalid_post(post)
  return unless post.nil?
  session[:error] = "Sorry, that post doesn't exist"
  redirect env['HTTP_REFERER']
end

get '/:post_id/comments' do
  posts = load_submissions_store
  @post = posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)

  @comments = @post.replies
  erb :comments
end

post '/:post_id/delete' do
  posts = load_submissions_store
  post = posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(post)

  if session[:user_name] != post.user_name
    session[:error] = 'Posts can only be deleted by the user that submitted them'
  else
    post.switch_to_deleted
    update_submissions_store(posts)
    session[:success] = 'Post successfully deleted!'
  end
  redirect '/'
end

def comment_submission_error(comment_text)
  return unless comment_text.nil? || comment_text.strip.empty?
  'Sorry, comment must have text'
end

post '/:post_id/comments', auth: true do
  post_id = params[:post_id]
  comment_text = params[:text]
  posts = load_submissions_store
  @post = posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  @comments = @post.replies
  submission_error = comment_submission_error(comment_text)

  if submission_error
    session[:error] = submission_error
    erb :comments
  else
    @post.add_reply(comment_text, session[:user_name])
    update_submissions_store(posts)
    session[:success] = 'Comment successfully posted'
    redirect "/#{@post.id}/comments"
  end
end

def redirect_if_invalid_comment(comment)
  return unless comment.nil?
  session[:error] = "Sorry, that comment doesn't exist"
  redirect env['HTTP_REFERER']
end

get '/:post_id/comments/:comment_id/reply', auth: true do
  post_id = params[:post_id]

  posts = load_submissions_store
  @post = posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment_id = params[:comment_id]

  @comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(@comment)

  erb :comment_reply
end

post '/:post_id/comments/:comment_id/reply', auth: true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  comment_text = params[:text]

  posts = load_submissions_store
  @post = posts.detect { |post| post.id == post_id }

  redirect_if_invalid_post(@post)

  parent_comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(parent_comment)
  submission_error = comment_submission_error(comment_text)

  if submission_error
    session[:error] = submission_error
    redirect "/#{@post.id}/comments/#{comment_id}/reply"
    erb :comment_reply
  else
    parent_comment.add_reply(comment_text, session[:user_name])
    update_submissions_store(posts)
    session[:success] = 'Reply successfully submitted!'
    redirect "/#{@post.id}/comments"
  end
end

post '/:post_id/comments/:comment_id/delete', auth: true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  posts = load_submissions_store
  @post = posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(comment)

  if session[:user_name] != comment.user_name
    session[:error] = 'Only the user that submitted the comment can delete it'
    redirect "#{@post.id}/comments"
  else
    comment.switch_to_deleted
    update_submissions_store(posts)
    session[:success] = 'Comment successfully deleted'
    redirect "/#{@post.id}/comments"
  end
end

post '/:post_id/vote', auth: true do
  posts = load_submissions_store
  @post = posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)
  choice = params[:choice]

  case choice
  when 'upvote' then @post.upvote(session[:user_name])
  when 'downvote' then @post.downvote(session[:user_name])
  when 'remove' then @post.remove_vote(session[:user_name])
  end

  update_submissions_store(posts)

  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    status 204
  else
    redirect '/'
  end
end

post '/:post_id/:comment_id/vote', auth: true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  choice = params[:choice]

  posts = load_submissions_store
  @post = posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(comment)

  case choice
  when 'upvote' then comment.upvote(session[:user_name])
  when 'downvote' then comment.downvote(session[:user_name])
  when 'remove' then comment.remove_vote(session[:user_name])
  end

  update_submissions_store(posts)

  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    status 204
  else
    redirect "/#{@post.id}/comments"
  end
end
