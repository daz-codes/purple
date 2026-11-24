# Which paths, tracks and missions a player can play (docs/PLAN-phase-2.md, section 5a):
#
# - A path opens always, once the player has finished a number of missions on any path, or once
#   they've finished every mission on another path's first track.
# - A track opens with its path, once unlock_after missions on the track before it are finished.
#   The first track on a path has nothing before it.
# - A mission is open when its track is. The daily track is open to everyone.
# - Nothing ever locks again: a path or track the player has already played stays open, whatever the
#   counts say now (content can change under them).
#
# "Finished" means completed or stood down: an attempt that expired because the player walked away
# doesn't count. A visitor (nil user) has finished nothing, so sees what a new player would.
class User::Unlocks
  ENDED_BY_PLAYER = %w[ completed stood_down ].freeze

  def initialize(user)
    attempts = user ? user.mission_attempts : MissionAttempt.none
    @finished = attempts.where(status: ENDED_BY_PLAYER).distinct.pluck(:mission_id).to_set
    @played = attempts.distinct.pluck(:mission_id).to_set
  end

  def finished?(mission)
    @finished.include?(mission.id)
  end

  def open?(record)
    case record
    when Path then path_open?(record)
    when Track then track_open?(record)
    when Mission then track_open?(record.track)
    else raise ArgumentError, "can't unlock a #{record.class}"
    end
  end

  # What the player still has to do for a locked path or track to open, as a sentence.
  def opens_when(record)
    return if open?(record)

    if record.is_a?(Track) && path_open?(record.path)
      previous = previous_track(record)
      left = record.unlock_after - finished_on(previous)
      "Finish #{left} more #{"mission".pluralize(left)} on #{previous.title} to open this track."
    else
      path = record.is_a?(Track) ? record.path : record
      if path.opens_after_missions?
        left = path.opens_after_missions - @finished.size
        "Finish #{left} more #{"mission".pluralize(left)} on any path to open #{path.title}."
      else
        "Finish the #{first_track(path.opens_after_path)&.title || "first"} track on #{path.opens_after_path.title} to open #{path.title}."
      end
    end
  end

  private
    def path_open?(path)
      # The daily track is open to everyone, so playing it doesn't open the path it sits on.
      return true if played_on?(path.tracks.reject(&:daily?))

      case path.opens
      when "always" then true
      when "after_missions" then @finished.size >= path.opens_after_missions
      when "after_first_track" then (first = first_track(path.opens_after_path)) && track_finished?(first)
      end
    end

    def track_open?(track)
      return true if track.daily? || played_on?([ track ])
      return false unless path_open?(track.path)

      previous = previous_track(track)
      previous.nil? || finished_on(previous) >= track.unlock_after
    end

    def first_track(path)
      playable_tracks(path).first
    end

    # The listed, playable track before this one on its path.
    def previous_track(track)
      playable_tracks(track.path).take_while { |other| other != track }.last
    end

    def playable_tracks(path)
      path.tracks.select { |track| track.published? && !track.daily? && playable_missions(track).any? }.sort_by(&:position)
    end

    def playable_missions(track)
      track.missions.select(&:published?)
    end

    def finished_on(track)
      playable_missions(track).count { |mission| finished?(mission) }
    end

    def track_finished?(track)
      missions = playable_missions(track)
      missions.any? && missions.all? { |mission| finished?(mission) }
    end

    def played_on?(tracks)
      tracks.any? { |track| track.missions.any? { |mission| @played.include?(mission.id) } }
    end
end
