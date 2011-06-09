class SourceableInstitution < ActiveRecord::Base

  belongs_to :sourceable, :polymorphic => true
  belongs_to :holding_institution

  validates_presence_of :sourceable_type, :sourceable_id, :holding_institution_id
  validates_uniqueness_of :holding_institution_id, :scope => [:sourceable_id, :sourceable_type]
  
  @@record = true # enables or disables automatic creation of SourceableInstitutions when a sourceable is saved
  @@sourceable_classes = Array.new
  cattr_reader :sourceable_classes
  cattr_accessor :record

  def self.unsource_all(institution)
    delete_all(["holding_institution_id = ?", institution.id])

    @@sourceable_classes.each do |sourceable_class|
      sourceable_class.unsource
    end
  end
  
  def self.garbage_collect
    @@sourceable_classes.each do |sourceable_class|
      print "Garbage Collecting #{sourceable_class.name}..."
      sourceable_class.garbage_collect
      puts "done"
    end
  end

  def self.unsourced(options = {})
    classes = options[:classes] || @@sourceable_classes
    sql = []
    
    for sourceable_class in classes
      sql << "SELECT '#{sourceable_class.name}' AS sourceable_type, #{sourceable_class.table_name}.id AS sourceable_id FROM #{sourceable_class.table_name} LEFT OUTER JOIN sourceable_institutions ON sourceable_institutions.sourceable_type = '#{sourceable_class.name}' AND sourceable_institutions.sourceable_id = #{sourceable_class.table_name}.id WHERE sourceable_institutions.id IS NULL #{"AND #{sourceable_class.table_name}.derived = false" if sourceable_class.column_names.include?('derived')}"
    end
    
    sql = sql.join(" UNION ")
    
    # Add a limit and offset and assemble a count query if we want a paginated collection
    if options.key?(:page)
      options[:page] ||= 1
      options[:per] ||= 100
      options[:page] = options[:page].to_i
      options[:per] = options[:per].to_i
      
      count_sql = "SELECT COUNT(*) AS count FROM (" + sql + ") AS orphans"
      
      sql << " LIMIT #{options[:per]}"
      sql << " OFFSET #{(options[:page] - 1) * options[:per]}"
    end
    
    # Find all orphans of each type at once to reduce the number of queries
    records = ActiveRecord::Base.connection.execute(sql).group_by {|entry| entry['sourceable_type'] }.collect do |sourceable_type, entries|
      sourceable_type.constantize.find(entries.collect {|entry| entry['sourceable_id'] })
    end.flatten
    
    # Masquerade as a paginated collection
    if options.key?(:page)
      count = count_by_sql(count_sql)
      
      records.instance_eval <<-EVAL
            def current_page
              #{options[:page] || 1}
            end
            def num_pages
              #{count}
            end
            def limit_value                                                                               
              #{options[:per]}
            end
      EVAL
    end
    
    return records
  end
end