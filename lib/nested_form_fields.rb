require "nested_form_fields/version"

module NestedFormFields
  module Rails
    class Engine < ::Rails::Engine
    end
  end
end

module ActionView::Helpers

  class FormBuilder

    def nested_fields_for(record_name, record_object = nil, fields_options = {}, &block)
      fields_options, record_object = record_object, nil if record_object.is_a?(Hash) && record_object.extractable_options?
      fields_options[:builder] ||= options[:builder]
      fields_options[:parent_builder] = self
      fields_options[:wrapper_tag] ||= :fieldset
      fields_options[:wrapper_options] ||= {}
      fields_options[:namespace] = fields_options[:parent_builder].options[:namespace]

      return fields_for_association_with_template(record_name, record_object, fields_options, block)
    end


    def add_nested_fields_link association, text = nil, html_options = {}, &block
      html_class = html_options.delete(:class) || {}
      html_data = html_options.delete(:data) || {}

      if association_type(association) == :has_one && object.send(association)
        html_options[:style] = html_options[:style] ? html_options[:style] + ';' + 'display:none' : 'display:none'
      end

      args = []
      args << (text || "Add #{association.to_s.singularize.humanize}") unless block_given?
      args << ''
      args << { class: "#{html_class.empty? ? '' : html_class} add_nested_fields_link",
                data: { association_path: association_path(association.to_s),
                        object_class: association.to_s.singularize,
                        association_type: association_type(association).to_s}.merge(html_data),
              }.merge(html_options)

      @template.link_to *args, &block
    end

    def remove_nested_fields_link text = nil, html_options = {}, &block
      html_class = html_options.delete(:class) || {}
      html_data = html_options.delete(:data) || {}

      args = []
      args << (text || 'x') unless block_given?
      args << ''
      args << { class: "#{html_class.empty? ? '' : html_class} remove_nested_fields_link",
                data: { delete_association_field_name: delete_association_field_name,
                        object_class: @object.class.name.underscore.downcase,
                        association_path: association_path }.merge(html_data),
              }.merge(html_options)

      @template.link_to *args, &block
    end


    private

    def fields_for_association_with_template(association_name, association, options, block)
      name = "#{object_name}[#{association_name}_attributes]"
      association = convert_to_model(association)

      if association.respond_to?(:persisted?)
        association = [association]
      elsif !association.respond_to?(:to_ary)
        association = if association_type(association_name) == :has_one
          []
        else
          @object.send(association_name)
        end
      end

      output = ActiveSupport::SafeBuffer.new
      association.each do |child|
        wrapper_options = options[:wrapper_options].clone || {}
        if child._destroy == true
          wrapper_options[:style] = wrapper_options[:style] ? wrapper_options[:style] + ';' + 'display:none' : 'display:none'
        end
        child_index = association_type(association_name) == :has_one ? '' : "[#{options[:child_index] || nested_child_index(name)}]"
        output << nested_fields_wrapper(association_name, options[:wrapper_tag], options[:legend], wrapper_options) do
          fields_for_nested_model("#{name}#{child_index}", child, options, block)
        end
      end

      output << nested_model_template(name, association_name, options, block)
      output
    end


    def nested_model_template name, association_name, options, block
      for_template = self.options[:for_template]

      # Render the outermost template in a script tag to avoid it from being submited with the form
      # Render all deeper nested templates as hidden divs as nesting script tags messes up the html.
      # When nested fields are added with javascript by using a template that contains nested templates,
      # the outermost nested templates div's are replaced by script tags to prevent those nested templates
      # fields from form subission.
      #
      @template.content_tag( for_template ? :div : :script,
                             type: for_template ? nil : 'text/html',
                             id: template_id(association_name),
                             class: for_template ? 'form_template' : nil,
                             style: for_template ? 'display:none' : nil ) do
        nested_fields_wrapper(association_name, options[:wrapper_tag], options[:legend], options[:wrapper_options]) do
          association_class = (options[:class_name] || association_name).to_s.classify.constantize
          index = association_type(association_name) == :has_one ? '' : "[#{index_placeholder(association_name)}]"
          fields_for_nested_model("#{name}#{index}",
                                   association_class.new,
                                   options.merge(for_template: true), block)
        end
      end
    end

    def template_id association_name
      "#{association_path(association_name)}_template"
    end

    def association_path association_name=nil
      ["#{object_name.gsub('][','_').gsub(/_attributes/,'').sub('[','_').sub(']','')}", association_name].compact.join('_')
    end

    def index_placeholder association_name
      "__#{association_path(association_name)}_index__"
    end

    def delete_association_field_name
      "#{object_name}[_destroy]"
    end

    def nested_fields_wrapper(association_name, wrapper_element_type, legend, wrapper_options)
      wrapper_options = add_default_classes_to_wrapper_options(association_name, wrapper_options.clone)
      @template.content_tag wrapper_element_type, wrapper_options do
        (wrapper_element_type==:fieldset && !legend.nil?)? ( @template.content_tag(:legend, legend, class: "nested_fields") + yield ) : yield
      end
    end

    def add_default_classes_to_wrapper_options(association_name, wrapper_options)
      default_classes = ["nested_fields", "nested_#{association_path(association_name)}"]
      wrapper_options[:class] = wrapper_options[:class].is_a?(String) ? wrapper_options[:class].split(" ") : wrapper_options[:class].to_a
      wrapper_options[:class] += default_classes
      wrapper_options
    end

    def association_type association_name
      object.class.reflect_on_association(association_name).macro
    end
  end
end
