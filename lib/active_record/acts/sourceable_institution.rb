class SourceableInstitution < ActiveRecord::Base

  belongs_to :sourceable, :polymorphic => true
  belongs_to :holding_institution

  validates_presence_of :sourceable_type, :sourceable_id, :holding_institution_id
  validates_uniqueness_of :holding_institution_id, :scope => [:sourceable_id, :sourceable_type]
  
  @@record = true # enables or disables automatic creation of SourceableInstitutions when a sourceable is saved
  @@sourceable_classes = Array.new
  cattr_reader :sourceable_classes
  cattr_accessor :record

  def self.garbage_collect
    @@sourceable_classes.each do |sourceable_class|
      print "Garbage Collecting #{sourceable_class.name}..."
      sourceable_class.garbage_collect
      puts "done"
    end
  end

  def self.unsourced(*args)
    classes = args.present? ? args : @@sourceable_classes
    sql = []
    
    for sourceable_class in classes
      sql << "SELECT '#{sourceable_class.class_name}' AS sourceable_type, #{sourceable_class.table_name}.id AS sourceable_id FROM #{sourceable_class.table_name} LEFT OUTER JOIN sourceable_institutions ON sourceable_institutions.sourceable_type = '#{sourceable_class.class_name}' AND sourceable_institutions.sourceable_id = #{sourceable_class.table_name}.id WHERE sourceable_institutions.id IS NULL #{"AND #{sourceable_class.table_name}.derived = false" if sourceable_class.column_names.include?('derived')}"
    end
    
    ActiveRecord::Base.connection.execute(sql.join(" UNION "))
  end
end