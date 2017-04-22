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
TIME_MEASURES_IN_SECONDS = {"seconds" => 1, "minutes" => SECONDS_PER_MINUTE,
                            "hours" => SECONDS_PER_HOUR, "days" => SECONDS_PER_DAY,
                            "months" => SECONDS_PER_MONTH, "years" => SECONDS_PER_YEAR }

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

set(:auth) do |_|
  condition do
    unless session[:user_name]
      if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
        halt 401
      else
        session[:error] = "Must be signed in to perfom this action"
        redirect env["HTTP_REFERER"]
      end
    end
  end
end

def load_posts
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  File.open("#{File.dirname(__FILE__)}/data/submissions.pstore", "w+") do |file|
    s3_client.get_object({ bucket:'miniredditapp', key:'submissions_pstore.txt'}, target: file)
  end
  @submission_store = PStore.new("#{File.dirname(__FILE__)}/data/submissions.pstore")
  @posts = @submission_store.transaction { @submission_store[:posts] } || []
end

def update_posts
  @submission_store.transaction { @submission_store[:posts] = @posts }
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  s3_client.put_object( {
    bucket: 'miniredditapp',
    body: File.read("#{File.dirname(__FILE__)}/data/submissions.pstore"),
    key: 'submissions_pstore.txt'
    })
end

def load_users
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  File.open("#{File.dirname(__FILE__)}/data/users.pstore", "w+") do |file|
    s3_client.get_object({ bucket:'miniredditapp', key:'users_pstore.txt'}, target: file)
  end
  @users_store = PStore.new("#{File.dirname(__FILE__)}/data/users.pstore")
  @users = @users_store.transaction { @users_store[:users] } || []
end

def update_users
  @users_store.transaction { @users_store[:users] = @users }
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  s3_client.put_object( {
    bucket: 'miniredditapp',
    body: File.read("#{File.dirname(__FILE__)}/data/users.pstore"),
    key: 'users_pstore.txt'
    })
end

helpers do
  def sort_posts
    @posts.sort_by { |post| post.score }.reverse
  end

  def sort_comments(comments)
    comments.sort_by { |comment| comment.score }.reverse
  end

  def list_comments(comments, indent = 0, &block)
    sort_comments(comments).each do |comment|
      block.call(comment, indent)
      list_comments(comment.replies, indent + 20, &block) if comment.replies
    end
  end

  def upvote_status(submission)
    submission.upvoted?(session[:user_name]) ? "selected" : "unselected"
  end

  def downvote_status(submission)
    submission.downvoted?(session[:user_name]) ? "selected" : "unselected"
  end

  def calculate_time_passed(time_submitted)
    seconds_passed = (Time.now - time_submitted)
    unit_to_use = "seconds"
    count = 1
    TIME_MEASURES_IN_SECONDS.each do |unit, num_seconds|
      if seconds_passed > num_seconds
        unit_to_use = unit
        count = seconds_passed.to_f / num_seconds
      else
        break
      end
    end
    if count.round <= 1
      unit_to_use = unit_to_use[0...-1]
    end
    "#{count.round} #{unit_to_use} ago"
  end
end

get "/" do
  load_posts
  erb :home, :layout => :layout
end

get "/submit_post", :auth => true do
  load_posts
  erb :submit_post, :layout => :layout
end

get "/register" do
  erb :register
end

def new_username_error(username)
  if username.nil?
    "Must enter something for your username"
  elsif username.strip.empty?
    "Username must include alphanumeric characters"
  elsif username.strip.size > 20
    "Username must be less than 20 characters long"
  elsif username =~ /[^\w\s]/
    "Username can only include alphanumeric chacters and spaces"
  elsif @users.map { |user| user.name}.include?(username.strip)
    "Sorry, that username is already taken"
  end
end

def new_password_error(password)
  if password.nil?
    "Must enter something for your password"
  elsif password.strip.empty?
    "Password must include non-space characters"
  end
end

post "/register" do
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
    session["success"] = "Thanks for registering, #{session[:user_name]}"
    redirect "/"
  end
end

get "/signin" do
  erb :signin
end

def signin_attempt_error(username, password)
  attempted_user = @users.detect { |user| user.name == username }

  if attempted_user.nil?
    "Sorry, we don't recognize that username"
  elsif password.nil?
    "Must enter a password"
  elsif !attempted_user.correct_password?(password)
    session[:error] = "Invalid password.  Please try again"
  else
    nil
  end
end

post "/signin" do
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
    redirect "/"
  end
end

post "/signout" do
  session.delete(:user_name)
  session[:success] = "Successfully signed out"
  redirect "/"
end

def post_submission_error(title, link)
  if title.strip.empty? || link.strip.empty?
    "Must enter a title and link"
  elsif title.size > 100
    "Title length must be 100 characters or less"
  elsif link[0..3] != "http"
    "Link must be an http address"
  end
end

post "/submit_post", :auth => true do
  title = params[:title]
  link = params[:link]

  submission_error = post_submission_error(title, link)

  if submission_error
    session[:error] = submission_error
    erb :submit_post
  else
    load_posts
    used_ids = @posts.map(&:id)
    new_post = Post.new(title, link, session[:user_name], used_ids)
    @posts << new_post
    update_posts
    session[:success] = "Post successfully submitted!"
    redirect "/"
  end
end

def redirect_if_invalid_post(post)
  if post.nil?
    session[:error] = "Sorry, that post doesn't exist"
    redirect "/"
  end
end

get "/:post_id/comments" do
  load_posts
  @post = @posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)

  @comments = @post.replies
  erb :comments
end

post "/:post_id/delete" do
  load_posts
  @post = @posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)

  if session[:user_name] != @post.user_name
    session[:error] = "Posts can only be deleted by the user that submitted them"
    erb :home, :layout => :layout
  else
    @post.switch_to_deleted
    update_posts
    session[:success] = "Post successfully deleted!"
    erb :home, :layout => :layout
  end
end

def comment_submission_error(comment_text)
  if comment_text.nil? || comment_text.strip.empty?
    "Sorry, comment must have text"
  end
end

post "/:post_id/comments", :auth => true do
  post_id = params[:post_id]
  comment_text = params[:text]

  load_posts
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  @comments = @post.replies
  submission_error = comment_submission_error(comment_text)

  if submission_error
    session[:error] = submission_error
    erb :comments, :layout => :layout
  else
    @post.add_reply(comment_text, session[:user_name])
    update_posts
    session[:success] = "Comment successfully posted"
    redirect "/#{@post.id}/comments"
  end
end


def redirect_if_invalid_comment(comment)
  if comment.nil?
    session[:error] = "Sorry, that comment doesn't exist"
    redirect "/#{@post.id}/comments"
  end
end

get "/:post_id/comments/:comment_id/reply", :auth => true do
  post_id = params[:post_id]

  load_posts
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  @comment_id = params[:comment_id]

  comment = Comment.find(@post.replies, @comment_id)
  redirect_if_invalid_comment(comment)

  erb :comment_reply
end

post "/:post_id/comments/:comment_id/reply", :auth => true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  comment_text = params[:text]

  load_posts
  @post = @posts.detect { |post| post.id == post_id }

  redirect_if_invalid_post(@post)

  parent_comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(parent_comment)
  submission_error = comment_submission_error(comment_text)

  if submission_error
    session[:error] = submission_error
    redirect "/#{@post.id}/comments/#{comment_id}/reply"
    erb :comment_reply, :layout => :layout
  else
    parent_comment.add_reply(comment_text, session[:user_name])
    update_posts
    session[:success] = "Reply successfully submitted!"
    redirect "/#{@post.id}/comments"
  end
end

post "/:post_id/comments/:comment_id/delete", :auth => true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  load_posts
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment = Comment.find(@post.replies, comment_id)
  redirect_if_invalid_comment(comment)

  if session[:user_name] != comment.user_name
    session[:error] = "Only the user that submitted the comment can delete it"
    redirect "#{@post.id}/comments"
  else
    comment.switch_to_deleted
    update_posts
    session[:success] = "Comment successfully deleted"
    redirect "/#{@post.id}/comments"
  end
end

post "/:post_id/vote", :auth => true do
  load_posts
  @post = @posts.detect { |post| post.id == params[:post_id] }
  redirect_if_invalid_post(@post)

  case params["choice"]
  when "upvote" then @post.upvote(session[:user_name])
  when "downvote" then @post.downvote(session[:user_name])
  when "remove" then @post.remove_vote(session[:user_name])
  end

  update_posts

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    redirect "/"
  end
end

post "/:post_id/:comment_id/vote", :auth => true do
  post_id = params[:post_id]
  comment_id = params[:comment_id]
  choice = params[:choice]

  load_posts
  @post = @posts.detect { |post| post.id == post_id }
  redirect_if_invalid_post(@post)

  comment = Comment.find(@post.replies, comment_id)

  if comment.nil?
    session[:error] = "Sorry, that comment doesn't exist"
    erb :comments, :layout => :layout
  else
    case choice
    when "upvote" then comment.upvote(session[:user_name])
    when "downvote" then comment.downvote(session[:user_name])
    when "remove" then comment.remove_vote(session[:user_name])
    end

    update_posts

    if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
      status 204
    else
      redirect "/#{@post.id}/comments"
    end
  end
end
