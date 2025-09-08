# config/initializers/secure_link_to.rb
module SecureLinkTo
  def link_to(name = nil, options = nil, html_options = nil, &block)
    path = recognize_safe_path(options)

    return super unless path && user_signed_in?

    model = resolve_model_from(path[:controller])
    action = normalize_action(path[:action])

    return super if authorized?(action, model, path, html_options)

    # se não autorizado, não renderiza nada
    nil
  end

  private

  def recognize_safe_path(options)
    Rails.application.routes.recognize_path(options)
  rescue ActionController::RoutingError, NoMethodError, TypeError
    nil
  end

  def resolve_model_from(controller_name)
    return nil unless controller_name
    controller_name.singularize.camelize.safe_constantize
  end

  def normalize_action(action)
    case action
    when "index", "show"   then :read
    when "edit", "update"  then :update
    when "new", "create"   then :create
    when "destroy"         then :destroy
    else
      action&.to_sym
    end
  end

  def authorized?(action, model, path, html_options)
    return true unless model

    if action == :edit || (html_options&.dig(:method).to_s == "delete")
      record_id = path.except(:action, :controller).values.last
      record = model.where(id: record_id).first
      return can?(action, record)
    end

    can?(action, model)
  end
end
