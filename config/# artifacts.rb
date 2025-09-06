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
