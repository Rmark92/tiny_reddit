require_relative 'time_formatter'

class Submission
  attr_reader :id, :user_name, :timestamp, :replies

  def initialize(user_name)
    @user_name = user_name
    @timestamp = Time.now
    @upvotes = []
    @downvotes = []
    @replies = []
  end

  def score
    if self.deleted? then -10000
    else @upvotes.size - @downvotes.size
    end
  end

  def upvoted?(user_name)
    @upvotes.include? user_name
  end

  def downvoted?(user_name)
    @downvotes.include? user_name
  end

  def upvote(user_name)
    @upvotes << user_name unless @upvotes.include?(user_name)
    @downvotes.delete_if { |user_id| user_id == user_name }
  end

  def downvote(user_name)
    @downvotes << user_name unless @downvotes.include?(user_name)
    @upvotes.delete_if { |user_id| user_id == user_name }
  end

  def remove_vote(user_name)
    @downvotes.delete_if { |user_id| user_id == user_name }
    @upvotes.delete_if { |user_id| user_id == user_name }
  end

  def add_reply(text, user_name)
    @replies << ::Comment.new(text, user_name, self)
  end

  def num_replies
    @replies.inject(0) do |sum, reply|
      sum + 1 + reply.num_replies
    end
  end

  def switch_to_deleted
    @user_name = :deleted
    @text = :deleted
    @upvotes = :deleted
    @downvotes = :deleted
    @timestamp = :deleted
  end

  def timestamp_str
    TimeFormatter.calculate_elapsed(@timestamp)
  end

  def deleted?
    @user_name == :deleted
  end
end

class Comment < Submission
  attr_reader :text

  def initialize(text, user_name, parent)
    @text = text
    @id = generate_new_id(parent)
    super(user_name)
  end

  def self.find(comments, comment_id, depth = 0)
    max_depth = (comment_id.length / 5) - 1
    id_slice_start = depth * 5
    id_slice_end = id_slice_start + 5

    comment_found = nil

    comments.each do |comment|
      if depth == max_depth
        return comment if comment.id[id_slice_start...id_slice_end] ==
                          comment_id[id_slice_start...id_slice_end]
      elsif comment.id[id_slice_start...id_slice_end] ==
            comment_id[id_slice_start...id_slice_end]
        comment_found = self.find(comment.replies, comment_id, depth + 1)
      end
    end

    comment_found
  end

  def switch_to_deleted
    @text = :deleted
    super
  end

  private

  def generate_new_id(parent)
    id = nil
    loop do
      id = parent.instance_of?(self.class) ? parent.id + create_random_string : create_random_string
      break unless parent.replies.any? { |reply| reply.id == id }
    end
    id
  end

  def create_random_string
    rand_arr = []
    2.times { |_| rand_arr << ('a'..'z').to_a.sample }
    3.times { |_| rand_arr << rand(1..9).to_s }
    rand_arr.shuffle.join('')
  end
end

class Post < Submission
  attr_reader :id, :title, :link, :user_name, :timestamp, :replies

  def initialize(title, link, user_name, used_ids)
    @title = title
    @link = link
    @id = generate_new_id(used_ids)
    super(user_name)
  end

  def switch_to_deleted
    @title = :deleted
    @link = :deleted
    super
  end

  private

  def generate_new_id(used_ids)
    id = []
    loop do
      6.times { |_| id << ('a'..'z').to_a.sample }
      6.times { |_| id << rand(1..9).to_s }
      id = id.shuffle.join('')
      break unless used_ids.include?(id)
    end
    id
  end
end
