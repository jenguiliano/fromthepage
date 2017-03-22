class ChangePagesMeaningfulDefaultValue < ActiveRecord::Migration
  def up
    change_column_default(:works, :pages_are_meaningful, false)
  end
  def down
    change_column_default(:works, :pages_are_meaningful, true)
  end
end
