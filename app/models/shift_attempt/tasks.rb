# Blue's to-do list. A task is done when its completing link is used (M4), overdue once the clock
# passes its deadline, and resolved when it's done or can no longer be done.
module ShiftAttempt::Tasks
  extend ActiveSupport::Concern

  def task_completed?(task)
    done?(:complete_task, task.key)
  end

  def task_overdue?(task)
    !task_completed?(task) && clock_minutes > task.due_at_minute
  end

  # A task is resolved when it's done, or when every message that could complete it has been
  # reported. A task with no completing link at all isn't resolved: that's broken content, and it
  # mustn't end the shift.
  def all_tasks_resolved?
    tasks = shift.tasks.includes(links: :message)
    tasks.any? && tasks.all? do |task|
      completing = task.links.select(&:outcome_completes_task?)
      task_completed?(task) || (completing.any? && completing.all? { |link| reported?(link.message) })
    end
  end
end
