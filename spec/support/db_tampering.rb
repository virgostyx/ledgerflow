# B03c: what someone with direct access to the database could do - change a validated entry behind the back of the triggers of the application. The tables are the application's:
# a trigger can be switched off (inside the transaction of the spec, which takes it back at its end).
module DbTampering
  def tamper(*tables)
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE") # a table with deferred checks pending cannot be altered
    tables.each { |table| ApplicationRecord.connection.execute("ALTER TABLE #{table} DISABLE TRIGGER USER") }
    yield
  ensure
    tables.each { |table| ApplicationRecord.connection.execute("ALTER TABLE #{table} ENABLE TRIGGER USER") }
  end
end

RSpec.configure { |config| config.include DbTampering }
