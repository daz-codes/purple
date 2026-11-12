# Showing a message's full headers: the real sender address, reply-to and recipient behind the
# display name. Costs a minute.
module ShiftAttempt::HeaderExpandable
  extend ActiveSupport::Concern

  def expand_headers(message)
    acting_on(message) do
      reject "You've already expanded those headers." if headers_expanded?(message)

      record :expand_headers, message:
    end
  end

  def headers_expanded?(message)
    done?(:expand_headers, message.key)
  end
end
