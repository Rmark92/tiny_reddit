require 'bcrypt'

class User
  attr_reader :name

  def initialize(name, password)
    @name = name
    @hashed_password = BCrypt::Password.create(password)
  end

  def correct_password?(password_attempt)
    BCrypt::Password.new(@hashed_password) == password_attempt
  end
end
