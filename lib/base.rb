module  ActiveOrient
  require 'active_model'

# Base class for tableless IB data Models, extends ActiveModel API

  class Base
    extend ActiveModel::Naming
    extend ActiveModel::Callbacks
    include ActiveModel::Validations
    include ActiveModel::Serialization
    include ActiveModel::Serializers::Xml
    include ActiveModel::Serializers::JSON
    include OrientDB

    define_model_callbacks :initialize

# ActiveRecord::Base callback API mocks
    define_model_callbacks :initialize, :only => :after
    mattr_accessor :logger

# Used to read the metadata
    attr_reader :metadata

=begin
  Every Rest::Base-Object is stored in the @@rid_store
  The Objects are just references to the @@rid_store.
  Any Change of the Object is thus synchonized to any allocated variable.
=end
    @@rid_store = Hash.new

    def self.display_rid
      @@rid_store
    end

    def self.remove_rid obj
      @@rid_store.delete obj.rid
    end

    def self.get_rid rid
      rid =  rid[1..-1] if rid[0]=='#'
      @@rid_store[rid] 
    end

    def self.store_rid obj
      if obj.rid.present? && obj.rid.rid?
	  # return the presence of a stored object as true by the block
	  # the block is only executed if the presence is confirmed
	  # Nothing is returned from the class-method
	      if @@rid_store[obj.rid].present?
	        yield if block_given?
	      end
	      @@rid_store[obj.rid] = obj
	      @@rid_store[obj.rid]  # return_value
      else
	      obj # no rid-value: just return the obj
      end
    end

    def document
      @d
    end

=begin
If a opts hash is given, keys are taken as attribute names, values as data.
The model instance fields are then set automatically from the opts Hash.
=end

    def initialize attributes = {}, opts = {}
      logger.progname = "ActiveOrient::Base#initialize"
      @metadata = HashWithIndifferentAccess.new
      @d =  nil
      run_callbacks :initialize do
	if RUBY_PLATFORM == 'java' && attributes.is_a?( Document )
	  @d = attributes
	  attributes =  @d.values
	  @metadata[:class]      = @d.class_name
	  @metadata[:version]    = @d.version
	  @metadata[:cluster], @metadata[:record] = @d.rid[1,@d.rid.size].split(':')



	end
	attributes.keys.each do |att|
	  unless att[0] == "@" # @ identifies Metadata-attributes
	    att = att.to_sym if att.is_a?(String)
	    unless self.class.instance_methods.detect{|x| x == att}
	      self.class.define_property att, nil
	    else
	      #logger.info{"Property #{att.to_s} NOT assigned"}
	    end
	  end
	end

	if attributes['@type'] == 'd'  # document via REST
	  @metadata[:type]       = attributes.delete '@type'
	  @metadata[:class]      = attributes.delete '@class'
	  @metadata[:version]    = attributes.delete '@version'
	  @metadata[:fieldTypes] = attributes.delete '@fieldTypes'
	  if attributes.has_key?('@rid')
	    rid = attributes.delete '@rid'
	    cluster, record = rid[1,rid.size].split(':')
	    @metadata[:cluster] = cluster.to_i
	    @metadata[:record]  = record.to_i
	  end

	  if @metadata[:fieldTypes ].present? && (@metadata[:fieldTypes] =~ /=g/)
	    edges = @metadata['fieldTypes'].split(',').find_all{|x| x=~/=g/}.map{|x| x.split('=').first}
	    edges.each do |edge|
	      operator, *base_edge = edge.split('_')
	      base_edge = base_edge.join('_')
	      unless self.class.instance_methods.detect{|x| x == base_edge}
		## define two methods: out_{Edge}/in_{Edge} -> edge.
		self.class.define_property base_edge, nil
		self.class.send :alias_method, base_edge.underscore, edge
	      end
	    end
	  end
	end
	self.attributes = attributes # set_attribute_defaults is now after_init callback
      end
      #      puts "Storing #{self.rid} to rid-store"
      ActiveOrient::Base.store_rid self
    end

# ActiveModel API (for serialization)

    def attributes
      @attributes ||= HashWithIndifferentAccess.new
    end

    def attributes= attrs
      attrs.keys.each{|key| self.send("#{key}=", attrs[key])}
    end

=begin
  ActiveModel-style read/write_attribute accessors
  Autoload mechanism and data conversion are defined in the method "from_orient" of each class
=end

    def [] key
      iv = attributes[key.to_sym]
      if @metadata[:fieldTypes].present? && @metadata[:fieldTypes].include?(key.to_s+"=t")
	iv =~ /00:00:00/ ? Date.parse(iv) : DateTime.parse(iv)
      elsif iv.is_a? Array
	  OrientSupport::Array.new( work_on: self, work_with: iv.from_orient){ key.to_sym }
     elsif iv.is_a? Hash
	  OrientSupport::Hash.new( self, iv){ key.to_sym }
#     elsif iv.is_a? RecordMap 
 #      iv
#       puts "RecordSet detected"
      else
	iv.from_orient
      end
    end

    def []= key, val
      val = val.rid if val.is_a?( ActiveOrient::Model ) && val.rid.rid?
      attributes[key.to_sym] = case val
			       when Array
				 if val.first.is_a?(Hash)
				   v = val.map do |x|
				     if x.is_a?(Hash)
				       HashWithIndifferentAccess.new(x)
				     else
				       x
				     end
				   end
				   OrientSupport::Array.new(work_on: self, work_with: v )
				 else
				   OrientSupport::Array.new(work_on: self, work_with: val )
				 end
			       when Hash
				 HashWithIndifferentAccess.new(val)
			       else
				 val
			       end
    end

    def update_attribute key, value
      @attributes[key] = value
    end

    def to_model
      self
    end

# Noop methods mocking ActiveRecord::Base macros

    def self.attr_protected *args
    end

    def self.attr_accessible *args
    end

# ActiveRecord::Base association API mocks

    def self.belongs_to model, *args
      attr_accessor model
    end

    def self.has_one model, *args
      attr_accessor model
    end

    def self.has_many models, *args
      attr_accessor models
      define_method(models) do
        self.instance_variable_get("@#{models}") || self.instance_variable_set("@#{models}", [])
      end
    end

    def self.find *args
      []
    end

# ActiveRecord::Base misc

    def self.serialize *properties
    end

  end # Model
end # module
