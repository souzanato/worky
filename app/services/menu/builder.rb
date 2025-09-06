# app/services/menu/builder.rb
# frozen_string_literal: true

module Menu
  class Builder
    def initialize(view_context, items)
      @view  = view_context
      @items = Array(items)
    end

    def render
      @view.safe_join(@items.filter_map { |item| render_item(item) })
    end

    private

    def render_item(item)
      if item[:children].present?
        render_parent(item)
      else
        render_leaf(item)
      end
    end

    # -------- visibilidade + autorização --------
    def visible_by_flag?(item)
      cond = item[:if]
      return true if cond.nil?
      cond.respond_to?(:call) ? !!cond.call(@view) : !!cond
    end

    def authorized?(item)
      target = item.key?(:ability) ? item[:ability] : item[:text]
      action = (item[:ability_action] || :read)
      return true if target.blank?

      if @view.respond_to?(:can?)
        !!@view.can?(action, target.to_sym)
      elsif @view.respond_to?(:current_user) && @view.current_user.respond_to?(:can?)
        !!@view.current_user.can?(action, target.to_sym)
      else
        true
      end
    end

    # -------- parent (has-sub) --------
    def render_parent(item)
      return unless visible_by_flag?(item)

      children = Array(item[:children]).filter_map { |child|
        next unless visible_by_flag?(child) && authorized?(child)
        child
      }
      return if children.empty?
      return unless authorized?(item)

      # pai ativo se algum filho estiver ativo
      parent_active = children.any? { |c| active_for?(c) }
      parent_classes = [ "menu-item", "has-sub" ]
      parent_classes << "active" if parent_active

      @view.content_tag(:div, class: parent_classes.join(" ")) do
        toggler = @view.link_to("javascript:;", class: "menu-link") do
          @view.safe_join([
            icon_html(item[:icon]),
            @view.content_tag(:div, item[:text], class: "menu-text"),
            @view.content_tag(:div, "", class: "menu-caret")
          ].compact)
        end

        submenu = @view.content_tag(:div, class: "menu-submenu") do
          @view.safe_join(children.map { |child|
            # cada filho será WRAPPED pelo active_link_to (div.menu-item [active])
            render_leaf_link(child)
          })
        end

        @view.safe_join([ toggler, submenu ])
      end
    end

    # -------- leaf --------
    def render_leaf(item)
      return unless visible_by_flag?(item) && authorized?(item)
      render_leaf_link(item) # o wrap é feito pelo active_link_to
    end

    def render_leaf_link(item)
      path       = resolve_path(item[:path])
      link_opts  = { class: "menu-link" }
      active_opt = active_options(item)

      wrapper_class = [ "menu-item", item[:wrapper_class] ].compact.join(" ")

      # IMPORTANTE: wrap_tag + wrap_class => 'active' vai no WRAPPER (menu-item)
      # class_active: nil => não adiciona 'active' no <a.menu-link>
      @view.active_link_to(
        path,
        link_opts.merge(active_opt).merge(
          wrap_tag: :div,
          wrap_class: wrapper_class,
          class_active: nil
        )
      ) do
        @view.safe_join([
          icon_html(item[:icon]),
          @view.content_tag(:div,
            @view.safe_join([
              item[:text],
              (label_html(item[:label]) if item[:label])
            ].compact),
            class: "menu-text"
          )
        ].compact)
      end
    end

    # -------- helpers --------
    def icon_html(icon_class)
      return nil if icon_class.blank?
      @view.content_tag(:div, @view.content_tag(:i, "", class: icon_class), class: "menu-icon")
    end

    def label_html(text)
      @view.content_tag(:span, text, class: "menu-label")
    end

    def resolve_path(path)
      return "#" if path.blank?
      return path.call(@view) if path.respond_to?(:call)
      return @view.public_send(path) if path.is_a?(Symbol)
      path
    end

    # Opções pro active_link_to (a detecção continua com a gem)
    def active_options(item)
      if item[:active_if].respond_to?(:call)
        { active: ->(_) { !!item[:active_if].call(@view) } }
      elsif item[:active].present?
        { active: item[:active] } # :exclusive / :inclusive / {controller:, action:, ...}
      else
        {}
      end
    end

    # Boolean pra ativar o PAI quando algum filho estiver "ativo"
    def active_for?(item)
      return !!item[:active_if].call(@view) if item[:active_if].respond_to?(:call)

      if item[:active].is_a?(Hash)
        return active_hash_match?(item[:active])
      end

      # fallback simples: current_page? do path
      path = resolve_path(item[:path])
      return false if path.blank? || path == "#"
      !!@view.current_page?(path)
    end

    def active_hash_match?(h)
      h.all? do |k, v|
        case k.to_sym
        when :controller
          v = v.to_s
          @view.controller_name == v || @view.controller_path == v
        when :action
          @view.action_name.to_s == v.to_s
        when :params
          v.all? { |pk, pv| @view.params[pk].to_s == pv.to_s }
        else
          true
        end
      end
    end
  end
end
