# app/controllers/share_previews_controller.rb
class SharePreviewsController < ApplicationController
  skip_before_action :authenticate_user!  # ignora devise

  def workflow
    workflow = Workflow.find(params[:id])

    prepare_meta_tags(
      title: workflow.name,
      description: workflow.description.truncate(150),
      image: workflow.cover_image_url || view_context.image_url("default-share.png"),
      canonical: workflow_url(workflow)
    )

    render "share_previews/show", layout: "share_preview"
  end
end
