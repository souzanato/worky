# app/controllers/admin/logs_controller.rb
class Admin::LogsController < ApplicationController
  def show
    line_count = params[:id].to_i
    line_count = 200 if line_count <= 0 # default

    log_path = Rails.root.join("log", "#{Rails.env}.log")

    if File.exist?(log_path)
      logs = File.readlines(log_path).last(line_count)
      render plain: logs.join
    else
      render plain: "Log file not found", status: :not_found
    end
  end
end
