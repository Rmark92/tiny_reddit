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

SECONDS_PER_MINUTE = 60
SECONDS_PER_HOUR = 60 * SECONDS_PER_MINUTE
SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR
SECONDS_PER_MONTH = 31 * SECONDS_PER_DAY
SECONDS_PER_YEAR = 365 * SECONDS_PER_MONTH
TIME_MEASURES_IN_SECONDS = { 'seconds' => 1,
                             'minutes' => SECONDS_PER_MINUTE,
                             'hours' => SECONDS_PER_HOUR,
                             'days' => SECONDS_PER_DAY,
                             'months' => SECONDS_PER_MONTH,
                             'years' => SECONDS_PER_YEAR }.freeze

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
        session[:error] = 'Must be signed in to perfom this action'
        redirect env['HTTP_REFERER']
      end
    end
  end
end

def datastore_dir
  if ENV["RACK_ENV"] == "production"
    "#{File.dirname(__FILE__)}/data"
  else
    "#{File.dirname(__FILE__)}/test/data"
  end
end

def load_from_s3(file_name)
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  File.open("#{datastore_dir}/#{file_name}.pstore", 'w+') do |file|
    s3_client.get_object({ bucket: 'miniredditapp', key: "#{file_name}_pstore.txt" }, target: file)
  end
end

def write_to_s3(file_name)
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  s3_client.put_object(bucket: 'miniredditapp',
                       body: File.read("#{datastore_dir}/#{file_name}.pstore"),
                       key: "#{filename}_pstore.txt")
end


def load_submissions
  load_from_s3("submissions") if ENV["RACK_ENV"] == "production"
  @submission_store = PStore.new("#{datastore_dir}/submissions.pstore")
  @posts = @submission_store.transaction { @submission_store[:posts] } || []
end

def update_submissions
  @submission_store.transaction { @submission_store[:posts] = @posts }
  write_to_s3("submissions") if ENV["RACK_ENV"] == "production"
end

def load_users
  load_from_s3("users") if ENV["RACK_ENV"] == "production"
  @users_store = PStore.new("#{datastore_dir}/users.pstore")
  @users = @users_store.transaction { @users_store[:users] } || []
end

def update_users
  @users_store.transaction { @users_store[:users] = @users }
  write_to_s3("users") if ENV["RACK_ENV"] == "production"
end

helpers do
  def sort_posts
    @posts.sort_by(&:score).reverse
  end

  def sort_comments(comments)
    comments.sort_by(&:score).reverse
  end

  def list_comments(comments, indent = 0, &block)
    sort_comments(comments).each do |comment|
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

  def calculate_time_passed(time_submitted)
    seconds_passed = (Time.now - time_submitted)
    unit_to_use = 'seconds'
    count = 1
    TIME_MEASURES_IN_SECONDS.each do |unit, num_seconds|
      break unless seconds_passed > num_seconds
      unit_to_use = unit
      count = seconds_passed.to_f / num_seconds
    end
    unit_to_use = unit_to_use[0...-1] if count.round <= 1
    "#{count.round} #{unit_to_use} ago"
  end
end

get '/' do
  load_submissions
  erb :home
end

get '/submit_post', auth: true do
  load_submissions
  erb :submit_post
end

get '/register' do
  erb :register
end

def new_username_error(username)
  if username.nil?
    'Must enter something for your username'
  elsif username.strip.empty?
    'Username must include alphanumeric characters'
  elsif username.strip.size > 20
    'Username must be less than 20 characters long'
  elsif username =~ /[^\w\s]/
    'Username can only include alphanumeric chacters and spaces'
  elsif @users.map(&:name).include?(username.strip)
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
  load_users

  error_message = new_username_error(user_name) ||
                  new_password_error(password)

  if error_message
    session[:error] = error_message
    erb :register
  else
    current_user = User.new(user_name.strip, password)
    @users << current_user
    update_users

    session[:user_name] = current_user.name
    session[:success] = "Thanks for registering, #{session[:user_name]}"
    redirect '/'
  end
end

get '/signin' do
  erb :signin
end

def signin_attempt_error(username, password)
  attempted_user = @users.detect { |user| user.name == username }

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
  load_users

  signin_error_message = signin_attempt_error(username, password)

  if signin_error_message
    session[:error] = signin_error_message
    erb :signin
  else
    session[:user_name] = username
    session[:success] = "Welcome, #{session[:user_name]}"
    redirect '/'
  end
end

post '/signout' do
  session.delete(:user_name)
  session[:success] = 'Successfully signed out'
  redirect '/'
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
    load_submissions
    used_ids = @posts.map(&:id)
    new_post = Post.new(title, link, session[:user_name], used_ids)
    @posts << new_post
    update_submissions
    session[:success] = 'Post successfully submitted!'
    redirect '/'
  end
end

def redirect_if_invalid_post(post)
  return unless post.nil?
  session[:error] = "Sorry, that post doesn't exist"
  redirect '/'
end

get '/:post_id/comments' do
  load_submissions
  @post = @posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)

  @comments = @post.replies
  erb :comments
end

post '/:post_id/delete' do
  load_submissions
  @post = @posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)

  if session[:user_name] != @post.user_name
    session[:error] = 'Posts can only be deleted by the user that submitted them'
  else
    @post.switch_to_deleted
    update_submissions
    session[:success] = 'Post successfully deleted!'
  end
  erb :home
end

def comment_submission_error(comment_text)
  return unless comment_text.nil? || comment_text.strip.empty?
  'Sorry, comment must have text'
end

post '/:post_id/comments', auth: true do
  post_id = params[:post_id]
  comment_text = params[:text]

  load_submissions
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  @comments = @post.replies
  submission_error = comment_submission_error(comment_text)

  if submission_error
    session[:error] = submission_error
    erb :comments
  else
    @post.add_reply(comment_text, session[:user_name])
    update_submissions
    session[:success] = 'Comment successfully posted'
    redirect "/#{@post.id}/comments"
  end
end

def redirect_if_invalid_comment(comment)
  return unless comment.nil?
  session[:error] = "Sorry, that comment doesn't exist"
  redirect "/#{@post.id}/comments"
end

get '/:post_id/comments/:comment_id/reply', auth: true do
  post_id = params[:post_id]

  load_submissions
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  @comment_id = params[:comment_id]

  comment = Comment.find(@post.replies, @comment_id)
  redirect_if_invalid_comment(comment)

  erb :comment_reply
end

post '/:post_id/comments/:comment_id/reply', auth: true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  comment_text = params[:text]

  load_submissions
  @post = @posts.detect { |post| post.id == post_id }

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
    update_submissions
    session[:success] = 'Reply successfully submitted!'
    redirect "/#{@post.id}/comments"
  end
end

post '/:post_id/comments/:comment_id/delete', auth: true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  load_submissions
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(comment)

  if session[:user_name] != comment.user_name
    session[:error] = 'Only the user that submitted the comment can delete it'
    redirect "#{@post.id}/comments"
  else
    comment.switch_to_deleted
    update_submissions
    session[:success] = 'Comment successfully deleted'
    redirect "/#{@post.id}/comments"
  end
end

post '/:post_id/vote', auth: true do
  load_submissions
  @post = @posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)
  choice = params[:choice]

  case choice
  when 'upvote' then @post.upvote(session[:user_name])
  when 'downvote' then @post.downvote(session[:user_name])
  when 'remove' then @post.remove_vote(session[:user_name])
  end

  update_submissions

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

  load_submissions
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment = Comment.find(@post.replies, comment_id)

  if comment.nil?
    session[:error] = "Sorry, that comment doesn't exist"
    erb :comments
  else
    case choice
    when 'upvote' then comment.upvote(session[:user_name])
    when 'downvote' then comment.downvote(session[:user_name])
    when 'remove' then comment.remove_vote(session[:user_name])
    end

    update_submissions

    if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
      status 204
    else
      redirect "/#{@post.id}/comments"
    end
  end
end
