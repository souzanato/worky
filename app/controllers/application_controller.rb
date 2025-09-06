class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_paper_trail_whodunnit

  protected

  def configure_permitted_parameters
    # Sign up (registration)
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name])

    # Account update (editar perfil) — opcional, mas já deixo alinhado
    devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name])
  end
end
