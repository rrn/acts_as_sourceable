class SourceableInstitution < ActiveRecord::Base
  belongs_to :sourceable, :polymorphic => true
  belongs_to :holding_institution

  validates_presence_of :sourceable_type, :sourceable_id, :holding_institution_id
  
  # Removes sourceable institutions that no longer belong to a record or holding institution
  def self.garbage_collect
    ActiveRecord::Base.connection.select_values(SourceableInstitution.select("DISTINCT sourceable_type").to_sql).each do |sourceable_type|
      sourceable_table_name = sourceable_type.constantize.table_name
      sourceable_id_sql = SourceableInstitution.select("sourceable_institutions.id").where(:sourceable_type => sourceable_type).joins("LEFT OUTER JOIN #{sourceable_table_name} ON #{sourceable_table_name}.id = sourceable_institutions.sourceable_id").where("#{sourceable_table_name}.id IS NULL").to_sql
      SourceableInstitution.delete_all("id IN (#{sourceable_id_sql})")
    end
    SourceableInstitution.delete_all(["holding_institution_id NOT IN (?)", HoldingInstitution.all.collect(&:id)])
  end  
end