class AddCreatedByToCannedResponses < ActiveRecord::Migration[7.1]
  def change
    add_reference :canned_responses, :created_by, index: true
  end
end
