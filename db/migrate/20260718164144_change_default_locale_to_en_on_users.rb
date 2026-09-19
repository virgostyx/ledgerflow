class ChangeDefaultLocaleToEnOnUsers < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :locale, from: "fr", to: "en"
    User.update_all(locale: "en")
  end

  def down
    change_column_default :users, :locale, from: "en", to: "fr"
    User.update_all(locale: "fr")
  end
end
