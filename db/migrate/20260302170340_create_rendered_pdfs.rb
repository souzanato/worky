class CreateRenderedPdfs < ActiveRecord::Migration[8.0]
  def change
    create_table :rendered_pdfs do |t|
      t.timestamps
    end
  end
end
