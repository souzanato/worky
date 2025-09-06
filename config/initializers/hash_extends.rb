class Hash
  def hirb
    puts Hirb::Helpers::AutoTable.render(self)
  end
end
