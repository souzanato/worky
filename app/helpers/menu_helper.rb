# app/helpers/menu_helper.rb
module MenuHelper
  def sidebar_menu_data
    [
      {
        text: t("menu.clients.title"),
        icon: "fa fa-users",
        path: :clients_path,
        ability: "clients_menu",
        active: { controller: "clients" }
      },
      {
        text: t("menu.workflows.title"),
        icon: "fa fa-sitemap",
        path: :workflows_path,
        ability: "workflows_menu",
        active: { controller: "workflows" }
      },
      {
        text: t("menu.settings.title"),
        icon: "fa fa-cogs",
        ability: "settings_menu",
        children: [
          { text: t("menu.settings.children.users"),
            path: ->(v) { v.users_path },
            ability: "users_menu",
            active: { controller: "users" }
          }
        ]
      }
    ]
    # {
    #   text: t("menu.client.title"),
    #   icon: "fab fa-users",
    #   label: "NEW",
    #   path: :widgets_path,
    #   ability: :widgets,               # can :read, :widgets
    #   active: { controller: "widgets" }
    # },
  end

  def render_sidebar_menu(items = sidebar_menu_data)
    Menu::Builder.new(self, items).render
  end
end
