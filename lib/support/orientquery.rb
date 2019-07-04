require 'active_support/inflector'
module OrientSupport
  module Support

=begin
supports
  where: 'string'
  where: { property: 'value', property: value, ... }
  where: ['string, { property: value, ... }, ... ]

Used by update and select

_Usecase:_
 ORD.compose_where 'z=34', {u:6}
  => "where z=34 and u = 6" 
=end

    #
		def compose_where *arg , &b
			arg = arg.flatten.compact
			unless arg.blank? 
				g= generate_sql_list( arg , &b)
				"where #{g}" unless g.empty?
			end
    end

=begin
designs a list of "Key =  Value" pairs combined by "and" or the binding  provided by the block
   ORD.generate_sql_list  where: 25 , upper: '65' 
    => "where = 25 and upper = '65'"
   ORD.generate_sql_list(  con_id: 25 , symbol: :G) { ',' } 
    => "con_id = 25 , symbol = 'G'"
=end
		def generate_sql_list attributes = {}, &b
			fill = block_given? ? yield : 'and'
			case attributes 
			when ::Hash
				attributes.map do |key, value|
					case value
					when ActiveOrient::Model
						"#{key} = #{value.rrid}"
					when Numeric
						"#{key} = #{value}"
					when ::Array
						"#{key} in [#{value.to_orient}]"
					when Range
						"#{key} between #{value.first} and #{value.last} " 
					when DateTime
						"#{key} = date(\'#{value.strftime("%Y%m%d%H%M%S")}\',\'yyyyMMddHHmmss\')"
					when Date
						"#{key} = date(\'#{value.to_s}\',\'yyyy-MM-dd\')"
					else #  String, Symbol, Time, Trueclass, Falseclass ...
						"#{key} = \'#{value.to_s}\'"
					end
				end.join(" #{fill} ")
			when ::Array
				attributes.map{|y| generate_sql_list y, &b }.join( " #{fill} " )
			when String
				attributes
			when Symbol, Numeric
				attributes.to_s
			end		
		end
	end  # module 


  class MatchConnection
    attr_accessor :as
    def initialize edge: nil, direction: :both, as: nil, count: 1
      @edge = edge.is_a?( Class ) ?  edge.ref_name : edge.to_s
      @direction = direction  # may be :both, :in, :out
      @as =  as
      @count =  count
    end

    def direction= dir
      @direction =  dir
    end


		def direction
			fillup =  @edge.present? ? @edge : ''
			case @direction
			when :both
				" -#{fillup}- "
			when :in
				" <-#{fillup}- "
			when :out
				" -#{fillup}-> "
			when :out_vertex
				".outV() "
			when :in_vertex
				".inV() "
			when :both_vertex
				".bothV() "
			when :out_edge
				".outE(#{fillup}) "
			when :in_edge
				".inE(#{fillup}) "
			when :both_edge
				".bothE(#{fillup}) "
			end

		end

    def compose
      ministatement = @as.present? ? "{ as: #{@as} } " : "" 
     (1 .. @count).map{|x| direction }.join("{}") << ministatement

    end
    
  end  # class

  class MatchStatement
    include Support
    attr_accessor :as
    def initialize match_class=nil, **args
			reduce_class = ->(c){ c.is_a?(Class) ? c.ref_name : c.to_s }
      @misc  = []
      @where = []
      @while = []
      @maxdepth = 0
      @as =  nil


      @match_class = reduce_class[match_class]
      @as = @match_class.pluralize if @match_class.is_a?(String)

			args.each do |k, v|
				case k
				when :as
					@as = v
				when :while
					@while << v
				when :where
					@where << v
				when :class
					@match_class = reduce_class[v]

					@as = @match_class.pluralize
				else
					self.send k, v
				end
			end
		end
    

		def match_alias
			"as: #{@as }"
		end
		def while_s  value=nil
				if value.present?
					@while << value
					self
				elsif @while.present?
					"while: ( #{ generate_sql_list( @where ) }) "
				end
		end

#		alias while while_s
		
		def where  value=nil
				if value.present?
					@where << value
					self
				elsif @where.present?
					"where: ( #{ generate_sql_list( @where ) }) "
				end
		end

		def maxdepth=x
			@maxdepth = x
		end

		def method_missing method, *arg, &b
			@misc << method.to_s <<  generate_sql_list(arg) 
		end

		def misc
			@misc.join(' ') unless @misc.empty?
		end
		# used for the first compose-statement of a compose-query
		def compose_simple
			'{'+ [ "class: #{@match_class}", "as: #{@as}" , where ].compact.join(', ') + '}'
		end

		def compose

			'{'+ [ "class: #{@match_class}", 
					"as: #{@as}" , where, while_s, 
						@maxdepth >0 ? "maxdepth: #{maxdepth}": nil  ].compact.join(', ')+'}'
		end
		alias :to_s :compose
	end  # class


	QueryAttributes =  Struct.new( :kind, :projection, :where, :let, :order, :while, :misc, 
																:match_statements, :class, :return,  :aliases, :database, 
																:set, :group, :skip, :limit, :unwind  )
	
	class OrientQuery
    include Support


#
    def initialize  **args
			@q =  QueryAttributes.new args[:kind] ||	'select' ,
								[], #		 :projection 
								[], # :where ,
								[], # :let ,
								[], # :order,
								[], # :while,
								[] , # misc
								[],  # match_statements
								'',  # class
								'',  #  return
								[],   # aliases
								'',  # database
								[]   #set
			  args.each{|k,v| send k, v}
		end
		
		def start value
					@q[:kind] = :match
					@q[:match_statements] = [ MatchStatement.new( value) ]
					#  @match_statements[1] = MatchConnection.new
					self
		end

=begin
  where: "r > 9"                          --> where r > 9
  where: {a: 9, b: 's'}                   --> where a = 9 and b = 's'
  where:[{ a: 2} , 'b > 3',{ c: 'ufz' }]  --> where a = 2 and b > 3 and c = 'ufz'
=end
		def method_missing method, *arg, &b   # :nodoc: 
      @q[:misc] << method.to_s <<  generate_sql_list(arg) 
			self
    end

		def misc   # :nodoc:
			@q[:misc].join(' ') unless @q[:misc].empty?
		end

    def subquery  # :nodoc: 
      nil
    end

	
		def kind value=nil
			if value.present?
				@q[:kind] = value
				self
			else
			@q[:kind]
			end
		end
=begin
(only if kind == :match): connect

Add a connection to the match-query

A Match-Query alwas has an Entry-Stratement and maybe other Statements.
They are connected via " -> " (outE), "<-" (inE) or "--" (both).

The connection method adds a connection to the statement-stack. 

Parameters:
  direction: :in, :out, :both, :in_edge, :out_edge, :both_edge, :in_vertex, :out_vertex, :both_vertex
  edge_class: to restrict the Query on a certain Edge-Class
  count: To repeat the connection
  as:  Includes a micro-statement to finalize the Match-Query
       as: defines a output-variablet, which is used later in the return-statement

The method returns the OrientSupport::MatchConnection object, which can be modified further.
It is compiled by calling compose
=end

		def connect direction, edge_class: nil, count: 1, as: nil
			direction= :both unless [ :in, :out, :in_edge, :out_edge, :both_edge, :in_vertex, :out_vertex, :both_vertex].include? direction
			match_statements << m = OrientSupport::MatchConnection.new( direction: direction, edge: edge_class, count: count, as: as)
			self  #  return the object
		end

=begin
(only if kind == :match): statement

A Match Query consists of a simple start-statement
( classname and where-condition ), a connection followd by other Statement-connection-pairs.
It performs a sub-query starting at the given entry-point.

Statement adds a statement to the statement-stack.
Statement returns the created OrientSupport::MatchStatement-record for further modifications. 
It is compiled by calling »compose«. 

OrientSupport::OrientQuery collects any "as"-directive for inclusion  in the return-statement

Parameter (all optional)
 Class: classname, :where: {}, while: {}, as: string, maxdepth: >0 , 

=end
	def statement match_class= nil, **args
		match_statements <<  OrientSupport::MatchStatement.new( match_class, args )
		self  #  return the object
	end
=begin
  Output the compiled query
  Parameter: destination (rest, batch )
  If the query is submitted via the REST-Interface (as get-command), the limit parameter is extracted.
=end

		def compose(destination: :batch)
			if kind.to_sym == :match
				unless @q[:match_statements].empty?
					match_query =  kind.to_s.upcase + " "+ @q[:match_statements][0].compose 
					match_query << @q[:match_statements][1..-1].map( &:compose ).join
					match_query << " RETURN "<< (@q[:match_statements].map( &:as ).compact | @q[:aliases]).join(', ')
				end
			elsif kind.to_sym == :update
				return_statement = "return after " + ( @q[:aliases].empty? ?  "$this" : @q[:aliases].first.to_s)
				[ kind, @q[:database], set, where, return_statement ].compact.join(' ')
			elsif destination == :rest
				[ kind, projection, from, let, where, subquery,  misc, order, group_by, unwind, skip].compact.join(' ')
			else
				[ kind, projection, from, let, where, subquery,  misc, order, group_by, limit, unwind, skip].compact.join(' ')
			end
		end
		alias :to_s :compose

=begin
	from can either be a Databaseclass to operate on or a Subquery providing data to query further
=end


		def from arg = nil
			if arg.present?
				@q[:database] = case arg
												when ActiveOrient::Model   # a single record
													arg.rrid
												when OrientQuery	      # result of a query
													' ( '+ arg.to_s + ' ) '
												when Class
													arg.ref_name
												else
													if arg.to_s.rid?	  # a string with "#ab:cd"
														arg
													else		  # a database-class-name
														arg.to_s  
													end
												end
				self
			elsif  @q[:database].present? # read from
				"from #{@q[:database]}" 
			end
		end


		def order  value = nil
			if value.present?
				@q[:order] << value
			elsif @q[:order].present?

				"order by " << @q[:order].compact.flatten.map do |o|
					case o
					when String, Symbol, Array
						o.to_s
					else
						o.map{|x,y| "#{x} #{y}"}.join(" ")
					end  # case
				end.join(', ')
			else
				''
			end # unless
		end	  # def


    def database_class            # :nodoc:
  	    @q[:database]
    end

    def database_class= arg   # :nodoc:
  	  @q[:database] = arg 
    end

		def where  value=nil     # :nodoc:
			if value.present?
				@q[:where] << value
				self
			elsif @q[:where].present?
				"where #{ generate_sql_list( @q[:where] ) }"
			end
		end
		def distinct d
			@q[:projection] << "distinct " +  generate_sql_list( d ){ ' as ' }
			self
		end

class << self
		def mk_simple_setter *m
			m.each do |def_m|
				define_method( def_m ) do | value=nil |
						if value.present?
							@q[def_m]  = value
							self
						elsif @q[def_m].present?
						 "#{def_m.to_s}  #{generate_sql_list(@q[def_m]){' ,'}}"
						end
				end
			end
		end
		def mk_let_set_setter *m
			m.each do |def_m|
				define_method( def_m  ) do | value = nil |
					if value.present?
						@q[def_m] << value
						self
					elsif @q[def_m].present?
						"let " << @q[def_m].map do |s|
																		case s
																		when String
																			s
																		when ::Array
																			s.join(',  ')
																		when ::Hash  ### is not recognized in jruby
																			#	      else
																			s.map{|x,y| "$#{x} = (#{y})"}.join(', ')
																		end
																end.join(', ')
					end # branch
				end     # def_method
			end  # each
			end  #  def
end # class << self
		mk_simple_setter :limit, :skip, :unwind , :set
#		mk_let_set_setter :set

		def let       value = nil
			if value.present?
				@q[:let] << value
				self
			elsif @q[:let].present?
				"let " << @q[:let].map do |s|
					case s
					when String
						s
					when ::Array
						s.join(',  ')
					when ::Hash  ### is not recognized in jruby
						#	      else
						s.map{|x,y| "$#{x} = (#{y})"}.join(', ')
					end
				end.join(', ')
			end
		end

		def projection value= nil  # :nodoc:
			if value.present?
				@q[:projection] << value
				self
			elsif  @q[:projection].present?
				@q[:projection].compact.map do | s |
					case s
					when Array
						s.join(', ')
					when String, Symbol
						s.to_s
					else
						s.map{ |x,y| "#{x} as #{y}"}.join( ', ')
					end
				end.join( ', ' )
			end
		end

			
		
	  def group value = nil
			if value.present?
     	@q[:group] << value
			self
			elsif @q[:group].present?
			 "group by #{@q[:group].join(', ')}"
			end
    end
 
		alias order_by order 
		alias group_by group
		
		def get_limit  # :nodoc: 
    	@q[:limit].nil? ? -1 : @q[:limit].to_i
    end

		def expand item
			@q[:projection] =[ " expand ( #{item.to_s} )" ]
			self
    end

		# connects by adding {in_or_out}('edgeClass')
		def connect_with in_or_out, via: nil
			 argument = " #{in_or_out}(#{via.to_or if via.present?})"
		end
		# adds a connection
		#  in_or_out:  :out --->  outE('edgeClass').in[where-condition] 
		#              :in  --->  inE('edgeClass').out[where-condition]

		def nodes in_or_out = :out, via: nil, where: nil, expand: true
			 condition = where.present? ?  "[ #{generate_sql_list(where)} ]" : ""
			 start =  in_or_out 
			 the_end =  in_or_out == :in ? :out : :in
			 argument = " #{start}E(#{[via].flatten.map(&:to_or).join(',') if via.present?}).#{the_end}#{condition} "

			 if expand.present?
				 send :expand, argument
			 else
				 @q[:projection]  << argument 
			 end
			 self
		end

	end # class


end # module
