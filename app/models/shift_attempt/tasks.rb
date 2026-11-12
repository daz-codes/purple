# Blue's to-do list. A task is done from the portal page its legitimate link opens, and overdue once
# the clock passes its deadline.
module ShiftAttempt::Tasks
  extend ActiveSupport::Concern

  # Does the task on the portal page in the open tab.
  def complete_task
    acting_on do
      tab = current_tab_showing!("portal_task", "There's no task to do on this page.")
      reject "That task is already done." if task_completed?(tab.task)

      record :complete_task, message: tab.message, target_key: tab.task.key, result: tab.source
    end
  end

  def task_completed?(task)
    done?(:complete_task, task.key)
  end

  def task_overdue?(task)
    !task_completed?(task) && clock_minutes > task.due_at_minute
  end
end
