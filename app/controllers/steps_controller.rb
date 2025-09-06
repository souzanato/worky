# app/controllers/steps_controller.rb
class StepsController < ApplicationController
  before_action :set_workflow
  before_action :set_step, only: [ :edit, :update, :destroy, :move_up, :move_down ]
  authorize_resource if defined?(CanCanCan)

  def new
    @step = @workflow.steps.build(order: (@workflow.steps.maximum(:order).to_i + 1))
    render layout: false
  end

  def create
    @step = @workflow.steps.build(step_params)
    if @step.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @workflow, notice: t(".created", default: "Step created.") }
      end
    else
      render :new, status: :unprocessable_entity, layout: false
    end
  end

  def edit
    render layout: false
  end

  def update
    if @step.update(step_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @workflow, notice: t(".updated", default: "Step updated.") }
      end
    else
      render :edit, status: :unprocessable_entity, layout: false
    end
  end

  def destroy
    @step.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @workflow, notice: t(".deleted", default: "Step deleted.") }
    end
  end

  def move_up   ; reorder_step(-1) ; end
  def move_down ; reorder_step(+1) ; end

  private
  def set_workflow
    @workflow = Workflow.find(params[:workflow_id])
  end

  def set_step
    @step = @workflow.steps.find(params[:id])
  end

  def step_params
    params.require(:step).permit(:title, :description, :order)
  end

  def reorder_step(delta)
    siblings = @workflow.steps.order(:order).to_a
    i = siblings.index(@step)
    j = i + delta
    target = siblings[j]
    if target
      Step.transaction do
        a, b = @step.order, target.order
        @step.update!(order: b)
        target.update!(order: a)
      end
    end
    respond_to do |format|
      format.turbo_stream { render "steps/reorder" }
      format.html { redirect_to @workflow }
    end
  end
end
