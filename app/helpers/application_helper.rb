module ApplicationHelper
  def current_date_and_time
    Time.now.strftime("%A, %B %d, %Y, %H:%M")
  end
end
