class Material < ActiveRecord::Base
  acts_as_sourceable :condition => false
end