class Prefix < ActiveRecord::Base
  validates :prefix, length: {in: 1..10}
end
