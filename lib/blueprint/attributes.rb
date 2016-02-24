module Blueprint
  class Attribute
    def initialize(persisted: nil, **options)
      @options   = options
      @persisted = persisted
    end

    def ==(other)
      to_h == other.to_h
    end

    def has?(*keys, **conditions)
      keys.none? do |key|
        @options.values_at(*key).compact.empty?
      end && conditions.all? do |key, value|
        [*@options[key]] & [*value] != []
      end
    end

    def persisted_options
      @options.select { |key, _| Blueprint.config.persisted_attribute_options.keys.include?(key) }
    end

    def to_h
      @options
    end

    def merge(options)
      self.class.new(persisted: @persisted, **@options, **options)
    end

    def to_persisted(**config)
      return merge(config) if @persisted
      self.class.new(persisted: true, name: @options[:name], type: @options[:type], options: persisted_options, **config)
    end

    def [](name)
      @options[name.to_sym]
    end

    def method_missing(name)
      self[name]
    end
  end

  class AttributeScope
    def initialize(scope)
      @scope   = scope
      @selects = []
      @rejects = []
    end

    def where(*keys, **conditions)
      @selects << proc do |_, attribute|
        attribute.has?(*keys, **conditions)
      end
      Attributes.new(filter)
    end

    def not(*keys, **conditions)
      @rejects << proc do |_, attribute|
        attribute.has?(*keys, **conditions)
      end
      Attributes.new(filter)
    end

    def filter
      select = proc { |scope, condition| scope.select(&condition) }
      reject = proc { |scope, condition| scope.reject(&condition) }

      scope = @selects.inject(@scope, &select)
      @rejects.inject(scope, &reject)
    end
  end

  class Attributes
    def initialize(attributes = nil)
      attributes  = Hash[attributes] if attributes.is_a?(Array)
      @attributes = attributes || {}
    end

    def add(name:, type:, **options)
      @attributes[name.to_sym] = Attribute.new(name: name.to_sym, type: type.to_sym, **options)
    end

    def diff(diff, type: nil)
      # TODO: Clean up
      added   = diff.slice(*(diff.keys - keys))
      changed = diff.to_diff_a(type) - to_diff_a(type) - added.to_diff_a(type)
      changed = Attributes.new(Hash[changed].map { |key, options| { key => Attribute.new(persisted: true, **options) } }.inject(&:merge))
      removed = slice(*(keys - diff.keys))

      { added: added, changed: changed, removed: removed }
    end

    def where(*keys, **conditions)
      AttributeScope.new(@attributes).where(*keys, **conditions)
    end

    def not(*keys, **conditions)
      AttributeScope.new(@attributes).not(*keys, **conditions)
    end

    def keys
      @attributes.keys
    end

    def slice(*keys)
      where(name: keys)
    end

    def to_h
      @attributes
    end

    def to_a
      @attributes.values
    end

    def to_persisted
      @attributes.each do |name, attribute|
        @attributes[name] = attribute.to_persisted
      end
      self
    end

    def to_diff_a(type)
      if type
        to_h.map { |name, attr| [name, attr.send("to_#{type}").to_h] }
      else
        to_h.map { |name, attr| [name, attr.to_h] }
      end
    end

    def [](name)
      @attributes[name.to_sym]
    end

    def method_missing(name)
      self[name]
    end
  end
end
