# app/controllers/artifacts_controller.rb
class ArtifactsController < ApplicationController
  before_action :set_resource

  def new
    @artifact = @resource.artifacts.build
    render layout: false
  end

  def edit
    @artifact = @resource.artifacts.find(params[:id])
    render layout: false
  end

  def update
    @artifact = @resource.artifacts.find(params[:id])
    if @artifact.update(artifact_params)
      @artifact.upsert_to_pinecone
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @resource, notice: "Updated" }
      end
    else
      render :edit, status: :unprocessable_entity, layout: false
    end
  end

  def create
    @artifact = @resource.artifacts.build(artifact_params)
    if @artifact.save
      @artifact.upsert_to_pinecone
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @resource, notice: t(".uploaded", default: "File uploaded successfully.") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.html { redirect_to @resource, alert: t(".upload_failed", default: "Upload failed.") }
      end
    end
  end

  def destroy
    @artifact = @resource.artifacts.find(params[:id])
    @artifact.destroy
    redirect_to @resource, notice: t(".deleted", default: "File deleted.")
  end

  def download
    artifact = Artifact.find(params[:id])

    if artifact.file.attached?
      filename = "#{artifact.safe_filename}#{artifact.file.filename.extension_with_delimiter}"
      send_data artifact.file.download,
                filename: filename,
                type: artifact.file.content_type,
                disposition: "attachment"
    else
      redirect_back fallback_location: root_path, alert: "File not found."
    end
  end

  private

  def set_resource
    if params[:workflow_id]
      @resource = Workflow.find(params[:workflow_id])
    elsif params[:client_id]
      @resource = Client.find(params[:client_id])
    elsif params[:workflow_execution_id]
      @resource = WorkflowExecution.find(params[:workflow_execution_id])
    end
  end


  def artifact_params
    params.require(:artifact).permit(:file, :title, :description, :content)
  end
end


# class ArtifactsController < ApplicationController
#   before_action :set_artifact, only: %i[ show edit update destroy ]

#   # GET /artifacts or /artifacts.json
#   def index
#     @artifacts = current_user.available_artifacts
#   end

#   # GET /artifacts/1 or /artifacts/1.json
#   def show
#   end

#   # GET /artifacts/new
#   def new
#     @artifact = Artifact.new
#   end

#   # GET /artifacts/1/edit
#   def edit
#   end

#   # POST /artifacts or /artifacts.json
#   def create
#     @artifact = Artifact.new(artifact_params)

#     respond_to do |format|
#       if @artifact.save
#         format.html { redirect_to @artifact, notice: "Artifact was successfully created." }
#         format.json { render :show, status: :created, location: @artifact }
#       else
#         format.html { render :new, status: :unprocessable_entity }
#         format.json { render json: @artifact.errors, status: :unprocessable_entity }
#       end
#     end
#   end

#   # PATCH/PUT /artifacts/1 or /artifacts/1.json
#   def update
#     respond_to do |format|
#       if @artifact.update(artifact_params)
#         format.html { redirect_to @artifact, notice: "Artifact was successfully updated.", status: :see_other }
#         format.json { render :show, status: :ok, location: @artifact }
#       else
#         format.html { render :edit, status: :unprocessable_entity }
#         format.json { render json: @artifact.errors, status: :unprocessable_entity }
#       end
#     end
#   end

#   # DELETE /artifacts/1 or /artifacts/1.json
#   def destroy
#     @artifact.destroy!

#     respond_to do |format|
#       format.html { redirect_to artifacts_path, notice: "Artifact was successfully destroyed.", status: :see_other }
#       format.json { head :no_content }
#     end
#   end

#   private
#     # Use callbacks to share common setup or constraints between actions.
#     def set_artifact
#       @artifact = Artifact.find(params.expect(:id))
#     end

#     # Only allow a list of trusted parameters through.
#     def artifact_params
#       params.expect(artifact: [ :title, :content ])
#     end
# end
