# "Which side do you want to try first?", asked once after signing up, and the side switcher on the
# dashboard. The preferred side only shapes what's suggested: both sides are always open.
class SidesController < ApplicationController
  def new
  end

  def create
    side = params[:side].to_s
    return redirect_to(new_side_path, alert: "Pick Blue or Red.") unless side.in?(User::Progression::SIDES)

    Current.user.choose_side(side)
    redirect_to params[:return_to] == "dashboard" ? root_path : (side == "blue" ? tracks_path : targets_path),
      status: :see_other, notice: side == "blue" ? "You're on the Blue team. Pick a track to start a shift." : "You're on the Red team. Pick a target."
  end
end
