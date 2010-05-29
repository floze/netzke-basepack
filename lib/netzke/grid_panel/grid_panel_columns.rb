module Netzke
  class GridPanel < Base
    module GridPanelColumns
      module ClassMethods
        # Columns to be displayed by the FieldConfigurator, "meta-columns". Each corresponds to a configuration
        # option for each column in the grid.
        def meta_columns
          [
            # Whether the column will be present in the grid, also in :hidden or :meta state. The value for this column will
            # always be sent to/from the JS grid to the server
            {:name => "included",      :attr_type => :boolean, :width => 40, :header => "Incl", :default_value => true},

            # The name of the column. May be any accessible method or attribute of the data_class.
            {:name => "name",          :attr_type => :string, :editor => :combobox, :width => 200},

            # The header for the column.
            {:name => "header",        :attr_type => :string, :width => 200},

            # The default value of this column. Is used when a new row in the grid gets created.
            {:name => "default_value", :attr_type => :string, :width => 200},

            # Whether the column is editable in the grid.
            {:name => "read_only",     :attr_type => :boolean, :header => "R/O"},

            # Whether the column will be in the hidden state (hide/show columns from the column menu, if it's enabled).
            {:name => "hidden",        :attr_type => :boolean},

            # Whether the column should have "grid filters" enabled 
            # (see here: http://www.extjs.com/deploy/dev/examples/grid-filtering/grid-filter-local.html)
            {:name => "with_filters",  :attr_type => :boolean, :default_value => true, :header => "Filters"},

            #
            # Below some rarely used parameters, hidden by default (you can always un-hide them from the column menu).
            #

            # The column's width
            {:name => "width",         :attr_type => :integer, :hidden => true},

            # Whether the column should be hideable
            {:name => "hideable",      :attr_type => :boolean, :default_value => true, :hidden => true},

            # Whether the column should be sortable (why change it? normally it's hardcoded)
            {:name => "sortable",      :attr_type => :boolean, :default_value => true, :hidden => true},

            # {:name => :renderer, :attr_type => :string, :editor => {:xtype => :jsonfield}},
          ]
        end
        
      end
      
      module InstanceMethods
        
        # Normalized columns for the grid, e.g.:
        # [{:name => :id, :hidden => true, ...}, {:name => :name, :editable => false, ...}, ...]
        def columns
          @columns ||= begin
            cols = NetzkeFieldList.read_list(global_id) if persistent_config_enabled?
            cols && cols.map!(&:symbolize_keys)
            cols || initial_columns
          end
        end

        # Stores modified columns in persistent storage
        def save_columns!
          NetzkeFieldList.write_list(global_id, columns)
        end

        def model_level_columns
          
        end

        # Columns that we fall back to when neither persistent columns, nor configured columns are present.
        # If there's a model-level field configuration, it's being used.
        # Otherwise the defaults straight from the ActiveRecord model ("netzke_attributes").
        # Override this method if you want to provide a fix set of columns in your subclass.
        def default_columns
          @default_columns ||= begin
            model_level_fields = NetzkeFieldList.read_list("#{data_class.name.tableize}_model_fields")
            model_level_fields && model_level_fields.map!(&:symbolize_keys) 
            model_level_fields ||= data_class.netzke_attributes
          end
        end

        # Columns that represent a smart merge of default_columns and columns passed during the configuration.
        def initial_columns
          # Normalize here, as from the config we can get symbols (names) instead of hashes
          columns_from_config = config[:columns] && normalize_attr_config(config[:columns])

          if columns_from_config
            # reverse-merge each column hash from config with each column hash from exposed_attributes (columns from config have higher priority)
            for c in columns_from_config
              corresponding_exposed_column = default_columns.find{ |k| k[:name] == c[:name] }
              c.reverse_merge!(corresponding_exposed_column) if corresponding_exposed_column
            end
            columns_for_create = columns_from_config
          else
            # we didn't have columns configured in widget's config, so, use the columns from the data class
            columns_for_create = default_columns
          end
          
          # Never use excluded columns
          columns_for_create.reject!{ |c| c[:excluded] }
          
          columns_for_create.each do |c|
            detect_association(c)
            set_default_header(c)
            set_default_editor(c)
            set_default_width(c)
            set_default_hidden(c)
            set_default_editable(c)
            set_default_sortable(c)
            set_default_filterable(c)
          end

          columns_for_create
        end
        
      end
      
      private
        def reflects_primary_key?(c)
          c[:name] == data_class.primary_key
        end
      
        def set_default_header(c)
          c[:header] ||= c.delete(:label) || c[:name].humanize
        end
        
        def set_default_editor(c)
          c[:editor] ||= editor_for_attr_type(c[:attr_type])
        end
        
        def set_default_width(c)
          c[:width] ||= 50 if c[:attr_type] == :boolean
          c[:width] ||= 150 if c[:attr_type] == :datetime
        end
        
        def set_default_hidden(c)
          c[:hidden] = true if reflects_primary_key?(c) && c[:hidden].nil?
        end
        
        def set_default_editable(c)
          c[:editable] = c[:read_only].nil? ? !reflects_primary_key?(c) : !c[:read_only]
          c.delete(:read_only)
        end
        
        def set_default_sortable(c)
          c[:sortable] = !c[:virtual]
        end
        
        def set_default_filterable(c)
          c[:filterable] = !c[:virtual]
        end
        
        # Returns editor's xtype for a column type
        def editor_for_attr_type(type)
          attr_type_to_editor_map[type]
        end
        
        def editor_for_association
          :combobox
        end
   
        # Returns a hash that maps a column type to the editor xtype. Override if you want different editors.
        def attr_type_to_editor_map
          {
            :integer => :numberfield,
            :boolean => :checkbox,
            :date => :datefield,
            :datetime => :xdatetime,
            :text => :textarea,
            :string => :textfield
          }
        end
      
        # Detects an association column and sets up the proper editor.
        # If a column is a foreign key (e.g. "category_id"), also renames the column into "normalized" association column, e.g.:
        #   category__name
        # If association doesn't respond to methods "name", "title" or "label", falls back to "id", e.g.:
        #   category__id
        def detect_association(c)
          # named as foreign key of some association?
          assoc = data_class.reflect_on_all_associations.detect{|a| a.primary_key_name == c[:name]}
          
          if assoc && !assoc.options[:polymorphic]
            assoc_method = %w{name title label id}.detect{|m| (assoc.klass.instance_methods + assoc.klass.column_names).include?(m) } || assoc.klass.primary_key
            c[:name] = "#{assoc.name}__#{assoc_method}"
          end
          
          # named with an double-underscore notation? surely an association column then
          if !assoc && c[:name].index('__')
            assoc_name, assoc_method = c[:name].split('__')
            assoc = data_class.reflect_on_association(assoc_name.to_sym)
          end
          
          if assoc
            assoc_column = assoc.klass.columns_hash[assoc_method]
            assoc_method_type = assoc_column.try(:type)
            
            if assoc_method_type
              # if association column is boolean, display a checkbox (or alike), otherwise - a combobox (or alike)
              c[:editor] = assoc_method_type == :boolean ? editor_for_attr_type(:boolean) : editor_for_association
            end
          end
        end
      
      def self.included(receiver)
        receiver.extend         ClassMethods
        receiver.send :include, InstanceMethods
      end
    end
  end
end