# The signed-in user's account page: their details, and every device they're signed in on.
class AccountsController < ApplicationController
  def show
    @sessions = Current.user.sessions.active.most_recent_first
  end
end
