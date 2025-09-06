# app/models/concerns/skip_confirmation_mail.rb
module SkipConfirmationMail
  extend ActiveSupport::Concern

  included do
    def send_on_create_confirmation_instructions
      # não faz nada
    end

    def send_confirmation_instructions
      # não faz nada
    end
  end
end
