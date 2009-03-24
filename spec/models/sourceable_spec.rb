require File.expand_path(File.join(File.dirname(__FILE__), '../spec_helper'))

describe "Sourceable" do
  before :all do
    connect
    $SITE = Site.create(:name =>"MOA", :short_name => "MOA")
  end
  before(:each) do
    @goat = Material.create(:name=>'goat', :derived => true, :definition => nil)
  end

  it "doesn't destroy Sourceable model if value assigned to :condition returns false" do
    @goat.destroy
    Material.find_by_name('goat').class.should == Material
  end
end

