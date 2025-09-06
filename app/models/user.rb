class User < ApplicationRecord
  has_paper_trail
  rolify after_add: ->(user, role) do
    user.confirm_user_after_role!(role)
    user.set_current_role(role, :add)
  end, after_remove: ->(user, role) do
    user.set_current_role(role, :remove)
  end
  after_create :attach_default_avatar

  include UserRoles
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable

  include SkipConfirmationMail

  validates :first_name, :last_name, :email, presence: true

  def to_admin
    add_role(:admin)
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def avatar_url
    "color-admin/img/user/#{avatar}"
  end

  # Callback do Rolify. Para métodos, AR passa apenas o "role" adicionado.
  def confirm_user_after_role!(role)
    return if confirmed?                                # já confirmado? nada a fazer

    # evita disparar e-mail de confirmação (se quiser)
    skip_confirmation_notification! if respond_to?(:skip_confirmation_notification!)

    # confirma a conta (Devise::Confirmable) e persiste
    confirm
  end

  def current_role
    User.find_role_by_code(self.current_role_code)
  end

  def available_users
    User.all.order(:first_name, :last_name)
  end

  def available_clients
    Client.all.order(:name)
  end

  def available_artifacts
    Artifact.all.order(:title)
  end

  def available_workflows
    if self.dev?
      Workflow.all
    end
  end

  def set_current_role(role, action)
    if action == :add
      if current_role_code.nil?
        update(current_role_code: role.name)
      end
    elsif action == :remove
      roles = self.roles.order(:created_at)
      if roles.any?
        update(current_role_code: roles.last.name)
      else
        update(
          current_role_code: nil,
          confirmed_at: nil,
          confirmation_token: Devise.friendly_token,
          confirmation_sent_at: Time.current
        )
      end
    end
  end

  # Alterna o estado de confirmação do usuário.
  def toggle_confirmation!
    if respond_to?(:confirmed_at) # Devise confirmable
      if confirmed?
        # "desconfirmar"
        self.confirmed_at = nil
        # opcional: preparar reenvio de confirmação
        self.confirmation_token     = Devise.friendly_token if respond_to?(:confirmation_token=)
        self.confirmation_sent_at   = Time.current if respond_to?(:confirmation_sent_at=)
      else
        # confirmar
        self.confirmed_at = Time.current
        # opcional: limpar token
        self.confirmation_token = nil if respond_to?(:confirmation_token=)
      end
      save!(validate: false)
    elsif has_attribute?(:confirmed) # coluna booleana simples
      update!(confirmed: !self[:confirmed])
    else
      raise "User não possui nem confirmed_at (Devise) nem boolean confirmed"
    end
  end

  private
  def attach_default_avatar
    return if avatar.present?

    update(avatar: "default.jpg")
  end
end
