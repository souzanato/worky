class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_paper_trail_whodunnit
  before_action :prepare_meta_tags, if: -> { request.get? }


  protected

  def configure_permitted_parameters
    # Sign up (registration)
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name])

    # Account update (editar perfil) — opcional, mas já deixo alinhado
    devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name])
  end

  def prepare_meta_tags(options = {})
    site_name   = Settings.reload!.ceo.site_name
    title       = I18n.t("titles.#{controller_path}.#{action_name}", default: controller_name.titleize)
    description = Settings.reload!.ceo.description
    image       = view_context.image_url(Settings.reload!.ceo.image) # coloca em app/assets/images
    current_url = request.url

    defaults = {
      site:        site_name,
      title:       title,
      description: description,
      keywords:    %w[rails app seo compartilhamento],
      canonical:   current_url,
      og: {
        url: current_url,
        site_name: site_name,
        title: title,
        image: image,
        description: description,
        type: "website"
      },
      twitter: {
        card: "summary_large_image",
        site: "@teuusuario", # teu @ no twitter (opcional)
        title: title,
        description: description,
        image: image
      }
    }

    options.reverse_merge!(defaults)
    set_meta_tags options
  end
end
