class AiCollectConfigsController < ApplicationController
  before_action :set_workflow
  before_action :set_ai_collect_config, only: %i[ show edit update destroy ]

  # GET /ai_collect_configs or /ai_collect_configs.json
  def index
    @ai_collect_configs = AiCollectConfig.all
  end

  # GET /ai_collect_configs/1 or /ai_collect_configs/1.json
  def show
  end

  # GET /ai_collect_configs/new
  def new
    @ai_collect_config = @workflow.ai_collect_configs.build
    render layout: false
  end

  # GET /ai_collect_configs/1/edit
  def edit
    @ai_collect_config = @workflow.ai_collect_configs.find(params[:id])
    render layout: false
  end

  # POST /ai_collect_configs or /ai_collect_configs.json


  def create
    @ai_collect_config = @workflow.ai_collect_configs.build(ai_collect_config_params)
    if @ai_collect_config.save
      respond_to do |format|
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /ai_collect_configs/1 or /ai_collect_configs/1.json
  def update
    @ai_collect_config = @workflow.ai_collect_configs.find(params[:id])
    if @ai_collect_config.update(ai_collect_config_params)
      respond_to do |format|
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity, layout: false
    end
  end

  # DELETE /ai_collect_configs/1 or /ai_collect_configs/1.json
  def destroy
    @ai_collect_config.destroy!
    @artifact.destroy
    redirect_to @resource, notice: t(".deleted", default: "File deleted.")
  end

  def destroy
    @ai_collect_config.destroy!
    respond_to do |format|
      format.turbo_stream
    end
  end

  private
    def set_workflow
      @workflow = Workflow.find(params[:workflow_id])
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_ai_collect_config
      @ai_collect_config = AiCollectConfig.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def ai_collect_config_params
      params.require(:ai_collect_config).permit(
        :title,
        :code,
        :description,
        :prompt,
        :ai_model,
        :active,
        :ask_language
      )
    end
end
