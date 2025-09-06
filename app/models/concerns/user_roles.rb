# app/models/concerns/user_roles.rb
module UserRoles
  extend ActiveSupport::Concern
  require "ostruct"

  RoleStruct = OpenStruct

  included do
    build_role_singletons         # Ex.: User.admin.name
    build_instance_role_predicates # Ex.: user.admin?
  end

  class_methods do
    def available_roles
      [
        RoleStruct.new(code: "admin", name: I18n.t("roles.admin")),
        RoleStruct.new(code: "dev", name: I18n.t("roles.dev"))
      ]
    end

    def find_role_by_code(code)
      roles[code]
    end

    # Hash { "admin" => #<OpenStruct ...>, ... } com indifferent_access
    def roles
      @__roles__ ||= available_roles.index_by(&:code).with_indifferent_access
    end

    def role?(code)
      roles.key?(code)
    end

    def role(code)
      roles[code]
    end

    # Rebuild seguro (remove antigos antes de recriar)
    def rebuild_roles!
      old_codes = roles.keys # captura antes do reset

      remove_role_singletons!(old_codes)
      remove_instance_role_predicates!(old_codes)

      @__roles__ = nil

      build_role_singletons
      build_instance_role_predicates
    end

    private

    # ========== Métodos de CLASSE por code ==========
    # Ex.: def self.admin; roles["admin"]; end
    def build_role_singletons
      roles.each_key do |code|
        define_singleton_method(code) { roles[code] }
      end
    end

    def remove_role_singletons!(codes)
      Array(codes).each do |code|
        if singleton_class.method_defined?(code)
          singleton_class.send(:remove_method, code)
        end
      end
    end

    # ========== Métodos de INSTÂNCIA por code ==========
    # Ex.: def admin?; has_role?("admin"); end
    def build_instance_role_predicates
      roles.each_key do |code|
        meth = method_name_for(code)
        # evita sobrescrever se já existir algo com mesmo nome
        next if instance_methods(false).include?(meth)

        define_instance_role_predicate(meth, code)
      end
    end

    def remove_instance_role_predicates!(codes)
      Array(codes).each do |code|
        meth = method_name_for(code)
        remove_method(meth) if instance_methods(false).include?(meth)
      end
    end

    # sanitize básico (caso alguém use code com hífen, espaços etc.)
    def method_name_for(code)
      clean = code.to_s.gsub(/[^\w]/, "_")
      :"#{clean}?"
    end

    def define_instance_role_predicate(meth, code)
      # define método de instância no próprio modelo (User)
      define_method(meth) do
        if respond_to?(:has_role?)
          has_role?(code) # rolify aceita string/symbol
        else
          false
        end
      end
    end
  end
end
