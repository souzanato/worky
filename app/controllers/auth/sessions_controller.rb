# frozen_string_literal: true

class Auth::SessionsController < Devise::SessionsController
  layout "auth"
  # before_action :configure_sign_in_params, only: [:create]

  # GET /resource/sign_in
  def new
    prepare_meta_tags(
      title: Settings.reload!.ceo.welcome_message,
      description: Settings.reload!.ceo.description,
      image: Settings.reload!.ceo.image,
      canonical: Settings.reload!.ceo.canonical
    )

    super
  end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
end
