# app/controllers/actions_controller.rb
class ActionsController < ApplicationController
  before_action :set_workflow
  before_action :set_step
  before_action :set_action, only: [ :edit, :update, :destroy, :move_up, :move_down ]
  authorize_resource if defined?(CanCanCan)

  def new
    @action = @step.actions.build(order: (@step.actions.maximum(:order).to_i + 1))
    render layout: false
  end

  def create
    @action = @step.actions.build(action_params)
    if @action.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @workflow, notice: t(".created", default: "Action created.") }
      end
    else
      render :new, status: :unprocessable_entity, layout: false
    end
  end

  def edit
    render layout: false
  end

  def update
    if @action.update(action_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @workflow, notice: t(".updated", default: "Action updated.") }
      end
    else
      render :edit, status: :unprocessable_entity, layout: false
    end
  end

  def destroy
    @action.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @workflow, notice: t(".deleted", default: "Action deleted.") }
    end
  end

  def move_up   ; reorder_action(-1) ; end
  def move_down ; reorder_action(+1) ; end

  private

  def set_workflow
    @workflow = Workflow.find(params[:workflow_id])
  end

  def set_step
    @step = @workflow.steps.find(params[:step_id])
  end

  def set_action
    @action = @step.actions.find(params[:id])
  end

  def action_params
    params.require(:workflow_action).permit(:title, :description, :order, :content, :has_ai_action, :allow_prompting, :has_prompt_generator, :artifact_name,  rag_artifact_ids: [], content_artifact_ids: [], ai_action_attributes: [ :id, :ai_model, :custom_attributes ])
  end

  def reorder_action(delta)
    siblings = @step.actions.order(:order).to_a
    i = siblings.index(@action)
    j = i + delta
    target = siblings[j]
    if target
      Action.transaction do
        a, b = @action.order, target.order
        @action.update!(order: b)
        target.update!(order: a)
      end
    end
    respond_to do |format|
      format.turbo_stream { render "actions/reorder" }
      format.html { redirect_to @workflow }
    end
  end
end
