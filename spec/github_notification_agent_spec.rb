require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::GithubNotificationAgent do
  before(:each) do
    @valid_options = Agents::GithubNotificationAgent.new.default_options
    @checker = Agents::GithubNotificationAgent.new(:name => "GithubNotificationAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
