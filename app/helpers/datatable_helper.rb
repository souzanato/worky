# app/helpers/datatable_helper.rb
module DatatableHelper
  def datatable_tag(options = {}, &block)
    # Opções padrão
    default_options = {
      class: "table table-striped table-bordered align-middle",
      data: {
        controller: "data-table",
        "data-table-page-length-value": 25,
        "data-table-language-value": I18n.locale.to_s,
        "data-table-responsive-value": true
      }
    }

    # Merge das opções
    merged_options = deep_merge_hash(default_options, options)

    # Gera a tag table
    content_tag(:table, merged_options, &block)
  end

  def datatable_column_defs(*args)
    column_defs = []

    args.each_with_index do |config, index|
      case config
      when :no_sort
        column_defs << { targets: [ index ], orderable: false }
      when :no_search
        column_defs << { targets: [ index ], searchable: false }
      when :actions
        column_defs << { targets: [ index ], orderable: false, searchable: false }
      when :date
        column_defs << { targets: [ index ], type: "date" }
      when :numeric
        column_defs << { targets: [ index ], type: "numeric" }
      when Hash
        column_defs << config.merge(targets: [ index ])
      end
    end

    column_defs.to_json
  end

  # Configurações pré-definidas para casos comuns
  def datatable_users_config
    {
      data: {
        "data-table-order-value": '[[1,"asc"]]',
        "data-table-column-defs-value": datatable_column_defs(
          :no_search,  # ID
          nil,         # Name
          nil,         # Email
          nil,         # Role
          nil,         # Confirmed
          :numeric,    # Sign ins
          :date,       # Last sign in
          :actions     # Actions
        )
      }
    }
  end

  def datatable_products_config
    {
      data: {
        "data-table-order-value": '[[1,"asc"]]',
        "data-table-column-defs-value": datatable_column_defs(
          :no_search,  # ID
          nil,         # Name
          :numeric,    # Price
          :date,       # Created at
          :actions     # Actions
        )
      }
    }
  end

  def datatable_simple_config
    {
      data: {
        "data-table-paging-value": false,
        "data-table-info-value": false,
        "data-table-searching-value": false
      }
    }
  end

  private

  def deep_merge_hash(hash1, hash2)
    result = hash1.dup
    hash2.each do |key, value|
      if result[key].is_a?(Hash) && value.is_a?(Hash)
        result[key] = deep_merge_hash(result[key], value)
      else
        result[key] = value
      end
    end
    result
  end
end
