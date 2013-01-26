require 'spec_helper'
ActiveRecord::Base.logger = Logger.new(nil)

describe 'acts_as_sourceable' do
  before(:each) do
    setup # Setup before each because rspec is stupid and won't do transactional fixtures
  end

  describe "helper methods" do
    it "should be able to group by class" do
      ActsAsSourceable::HelperMethods.group_by_class(@collection, @item1, @holding_institution).should == [[@holding_institution], [@collection], [@item1]]
    end

    it "should return an empty array for any class that isn't present when grouping by class" do
      ActsAsSourceable::HelperMethods.group_by_class(@collection, @holding_institution).should == [[@holding_institution], [@collection], []]
    end

    it "should be able to return grouped ids" do
      ActsAsSourceable::HelperMethods.group_ids_by_class(@collection, @item1, @holding_institution).should == [[@holding_institution.id], [@collection.id], [@item1.id]]
    end

    it "should return an empty array for any class that isn't present when grouping ids" do
      ActsAsSourceable::HelperMethods.group_ids_by_class(@collection, @holding_institution).should == [[@holding_institution.id], [@collection.id], []]
    end

    it "should order the grouped ids correctly when some classes are not present" do
      ActsAsSourceable::HelperMethods.group_ids_by_class(@collection).should == [[], [@collection.id], []]
    end

    describe "when garbage collecting" do
      it "should be able to fix registry entries that reference a single deleted source" do
        item3 = Item.create!
        record = SourceableRecord.create!
        record.add_source(item3)
        Item.delete(item3)
        ActsAsSourceable::HelperMethods.garbage_collect

        record.reload.sources.should == []
      end

      it "should be able to fix registry entries that reference a mixture of deleted and existing sources" do
        item3 = Item.create!
        record = SourceableRecord.create!
        record.add_source(@item1, item3)
        Item.delete(item3)
        ActsAsSourceable::HelperMethods.garbage_collect

        record.reload.sources.should == [@item1]
      end

      it "should update the sourceable's cached sourced flag when fixing registry entries that reference deleted sources" do
        item = Item.create!
        record = CachedSourceableRecord.create!
        record.add_source(item)
        Item.delete(item)
        ActsAsSourceable::HelperMethods.garbage_collect

        record.reload.sourced?.should be_false
      end

      it "should remove registry entries whose sourceable has been deleted" do
        item = Item.create!
        record = SourceableRecord.create!
        record.add_source(item)
        SourceableRecord.delete(record.id)
        ActsAsSourceable::HelperMethods.garbage_collect

        ActsAsSourceable::Registry.where(:sourceable_type => SourceableRecord, :sourceable_id => record.id).exists?.should be_false
      end
    end
  end

  shared_examples_for "acts_as_sourceable models with any options" do
    it "should be able to return all Items the record is sourced by" do
      pending
    end

    it "should be able to return all Collections the record is sourced by" do
      pending
    end

    it "should be able to return all HoldingInstitutions the record is sourced by" do
      pending
    end
  end

  describe "a model that just acts_as_sourceable" do
    before(:each) do
      @klass = SourceableRecord       
      @record = @klass.create!
    end

    # ADDING SOURCES

    it "should be able to add single Holding Institution as a source" do
      @record.add_source(@holding_institution)

      @record.sources.should == [@holding_institution]
    end

    it "should be able to add single Collection as a source" do
      @record.add_source(@collection)

      @record.sources.should == [@collection]
    end

    it "should be able to add single Item as a source" do
      item = Item.create!
      @record.add_source(item)

      @record.sources.should == [item]
    end

    it "should be able to add multiple records as sources" do
      @record.add_source(@item1)
      @record.add_source(@item2)
      @record.add_source(@collection)
      @record.add_source(@holding_institution)

      @record.sources.should include(@item1, @item2, @collection, @holding_institution)
    end

    it "should be able to add multiple records as sources all at once" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)

      @record.sources.should include(@item1, @item2, @collection, @holding_institution)
    end

    # REMOVING SOURCES

    it "should be able to remove single Holding Institution as a source" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @record.remove_source(@holding_institution)

      @record.sources.should include(@item1, @item2, @collection)
      @record.sources.should_not include(@holding_institution)
    end

    it "should be able to remove single Collection Institution as a source" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @record.remove_source(@collection)

      @record.sources.should include(@item1, @item2, @holding_institution)
      @record.sources.should_not include(@collection)
    end

    it "should be able to remove single Item Institution as a source" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @record.remove_source(@item2)

      @record.sources.should include(@item1, @collection, @holding_institution)
      @record.sources.should_not include(@item2)
    end

    it "should be able to remove multiple records as sources all at once" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @record.remove_source(@item1, @holding_institution)

      @record.sources.should include(@collection, @item2)
      @record.sources.should_not include(@item1, @holding_institution)
    end

    # SCOPING

    it "should be able to return all sourced records" do
      @klass.sourced.should == []
      @record.add_source(@item1, @holding_institution)
      @klass.sourced.should == [@record]
    end

    it "should be able to return all unsourced records" do
      @klass.unsourced.should == [@record]
      @record.add_source(@item1, @holding_institution)
      @klass.unsourced.should == []
    end

    it "should be able to return all records sourced by a specific Item, Collection, or HoldingInstitution" do
      @record.add_source(@item1, @holding_institution)

      @klass.sourced_by(@item1).should == [@record]
      @klass.sourced_by(@holding_institution).should == [@record]
      @klass.sourced_by(@collection).should == []
      @klass.sourced_by(@item2).should == []
    end

    # RELATIONS

    it "should be able to add sources on a relation" do
      @klass.add_source(@holding_institution)
      @record.sources.should == [@holding_institution]
    end

    it "should be able to remove sources on a relation" do
      @record.add_source(@holding_institution)
      @record.remove_source(@holding_institution)
      @record.sources.should == []
    end

    it "should be able to remove all sources on a class" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @klass.unsource
      @record.sources.should == []
    end    

    it "should be able to remove all sources on a relation" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @klass.sourced_by(@item1).unsource
      @record.sources.should == []
    end    

    # OTHER

    it "should unsource itself after being destroyed" do
      @record.add_source(@holding_institution)
      @record.destroy

      ActsAsSourceable::Registry.where(:sourceable_id => @record.id, :sourceable_type => @record.class).exists?.should be_false
    end

    it "should not be able to add a model other than and Item, Collection, or Holding Institution as a source" do
      pending
    end

    it_should_behave_like "acts_as_sourceable models with any options"
  end

  describe "a model that acts_as_sourceable" do
    before(:each) do
      @klass = SourceableThroughRecord
      @sourced_record = @klass.create!(:item_id => @item1.id)
      @unsourced_record = @klass.create!
    end

    # SCOPING

    it "should be able to return all sourced records" do
      @klass.sourced.should == [@sourced_record]
    end

    it "should be able to return all unsourced records" do
      @klass.unsourced.should == [@unsourced_record]
    end

    it "should be able to return all records sourced by a specific Item, Collection, or HoldingInstitution" do
      pending
    end

    it_should_behave_like "acts_as_sourceable models with any options"    
  end  

  describe "a model that acts_as_sourceable with a cache_column" do
    before(:each) do
      @klass = CachedSourceableRecord
      @record = @klass.create
    end

    # CACHE COLUMN

    it "should update the cache_column when adding sources" do
      @record.sourced.should be_false
      @record.add_source(@holding_institution)
      @record.sourced.should be_true
    end

    it "should update the cache column when removing an only source" do
      @record.add_source(@holding_institution)
      @record.remove_source(@holding_institution)
      @record.sourced.should be_false
    end

    it "should not update the cache column when removing one of many sources" do
      @record.add_source(@holding_institution, @collection)
      @record.remove_source(@holding_institution)
      @record.sourced.should be_true
    end

    it "should be able to remove all sources on a class" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @klass.unsource
      @record.sources.should == []
      @record.reload.sourced?.should be_false
    end    

    it "should be able to remove all sources on a relation" do
      @record.add_source(@item1, @item2, @collection, @holding_institution)
      @klass.sourced_by(@item1).unsource
      @record.sources.should == []
      @record.reload.sourced?.should be_false
    end

    it_should_behave_like "acts_as_sourceable models with any options"    
  end  

end

def setup
  Item.delete_all
  HoldingInstitution.delete_all
  Collection.delete_all
  SourceableRecord.delete_all
  SourceableThroughRecord.delete_all
  CachedSourceableRecord.delete_all
  ActsAsSourceable::Registry.delete_all

  @holding_institution = HoldingInstitution.create!
  @collection = Collection.create!
  @item1 = Item.create!
  @item2 = Item.create!  
end

def debug
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  yield
ensure
  ActiveRecord::Base.logger = Logger.new(nil)
end