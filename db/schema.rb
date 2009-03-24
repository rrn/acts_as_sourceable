ActiveRecord::Schema.define :version => 0 do
  create_table :materials, :force => true do |t|
    t.column "name", :string
    t.column "definition", :text
    t.column "derived", :boolean
  end

  create_table :sourceable_sites, :force => true do |t|
    t.column "sourceable_type", :string
    t.column "sourceable_id", :integer
    t.column "site_id", :integer
  end
  create_table :sites, :force => true do |t|
    t.column "short_name", :string
    t.column "name", :string
    t.column "mediator_href", :string
    t.column "site_href", :string
  end
end


