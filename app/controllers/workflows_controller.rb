# app/controllers/workflows_controller.rb
class WorkflowsController < ApplicationController
  before_action :set_workflow, only: [ :show, :edit, :update, :destroy ]
  authorize_resource if defined?(CanCan) || defined?(CanCanCan)

  def index
    @workflows = current_user.available_workflows
  end

  def show
    @steps = @workflow.steps.includes(:actions)
  end

  def new
    @workflow = Workflow.new
    @workflow.steps.build(order: 1) # já começa com um step vazio (opcional)
  end

  def edit
  end

  def create
    @workflow = Workflow.new(workflow_params)
    if @workflow.save
      redirect_to @workflow, notice: t(".created", default: "Workflow created successfully.")
    else
      flash.now[:alert] = t(".create_failed", default: "Could not create workflow.")
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @workflow.update(workflow_params)
      redirect_to @workflow, notice: t(".updated", default: "Workflow updated successfully.")
    else
      flash.now[:alert] = t(".update_failed", default: "Could not update workflow.")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workflow.destroy
    redirect_to workflows_path, notice: t(".deleted", default: "Workflow deleted.")
  end

  private

  def set_workflow
    @workflow = Workflow.find(params[:id])
  end

  def workflow_params
    params.require(:workflow).permit(
      :title, :description,
      steps_attributes: [
        :id, :title, :description, :order, :_destroy,
        { actions_attributes: [ :id, :title, :description, :order, :content, :ai_action, :_destroy, :has_prompt_generator, ai_action_attributes: [ :id, :ai_model, :custom_attributes ] ] }
      ]
    )
  end
end
