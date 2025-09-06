# config/breadcrumbs.rb

crumb :root do
  link "Home", root_path
end

crumb :users do
  link I18n.t("breadcrumbs.users", default: "users"), users_path
  parent :root
end

crumb :user do |user|
  link user.first_name, user_path(user)
  parent :users
end

crumb :edit_user do |user|
  link t("links.general.edit")&.downcase, edit_user_path(user)
  parent :user, user
end

crumb :new_user do
  link t("links.general.new")&.downcase, new_user_path
  parent :users
end


# Clients
crumb :clients do
  link I18n.t("breadcrumbs.clients", default: "clients"), clients_path
  parent :root
end

crumb :client do |client|
  link client.name, client_path(client)
  parent :clients
end

crumb :edit_client do |client|
  link I18n.t("breadcrumbs.edit", default: "Edit")
  parent :client, client
end

crumb :new_client do
  link I18n.t("breadcrumbs.new", default: "New")
  parent :clients
end

# workflows
crumb :workflows do
  link I18n.t("breadcrumbs.workflows", default: "workflows"), workflows_path
  parent :root
end

crumb :workflow do |workflow|
  link workflow.title, workflow_path(workflow)
  parent :workflows
end

crumb :edit_workflow do |workflow|
  link I18n.t("breadcrumbs.edit", default: "Edit")
  parent :workflow, workflow
end

crumb :new_workflow do
  link I18n.t("breadcrumbs.new", default: "New")
  parent :workflows
end

# artifacts
crumb :artifacts do
  link I18n.t("breadcrumbs.artifacts", default: "artifacts"), artifacts_path
  parent :root
end

crumb :artifact do |artifact|
  link artifact.title, artifact_path(artifact)
  parent :artifacts
end

crumb :edit_artifact do |artifact|
  link I18n.t("breadcrumbs.edit", default: "Edit")
  parent :artifact, artifact
end

crumb :new_artifact do
  link I18n.t("breadcrumbs.new", default: "New")
  parent :artifacts
end


# workflow_executions
crumb :workflow_executions do |client|
  link I18n.t("breadcrumbs.workflow_executions", default: "workflow_executions"), client_workflow_executions_path(client)
  parent :client, client
end

crumb :workflow_execution do |workflow_execution|
  link workflow_execution.id, client_workflow_execution_path(workflow_execution.client, workflow_execution)
  parent :workflow_executions, workflow_execution.client
end

crumb :edit_workflow_execution do |workflow_execution|
  link I18n.t("breadcrumbs.edit", default: "Edit")
  parent :workflow_execution, workflow_execution
end

crumb :new_workflow_execution do |client|
  link I18n.t("breadcrumbs.new", default: "New")
  parent :workflow_executions, client
end
