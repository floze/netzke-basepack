class BookPagingFormPanel < Netzke::Basepack::PagingFormPanel
  def default_config
    super.merge({
      :model => "Book",
      :scope => {:digitized => true},
      :mode => :lockable,
      :items => [{:layout => :hbox, :label_align => :top, :border => false, :defaults => {:border => false}, :items => [{
        :flex => 2,
        :layout => :form,
        :defaults => {:anchor => "-8"},
        :items => [:title, :notes]
      },{
        :flex => 1,
        :layout => :form,
        :defaults => {:anchor => "-8"},
        :items => [:author__name, :exemplars, :digitized]
      }]}]
    })
  end
end