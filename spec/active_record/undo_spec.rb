# frozen_string_literal: true

RSpec.describe ActiveRecord::Undo do
  it "has a version number" do
    expect(ActiveRecord::Undo::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end
