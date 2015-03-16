require 'spec_helper'

describe 'MakaraPostgreSQLAdapter' do

  let(:config){
    base = YAML.load_file(File.expand_path('spec/support/postgresql_database.yml'))['test']
    base['username'] = 'postgres' if ENV['TRAVIS']
    base
  }

  it 'should allow a connection to be established' do
    ActiveRecord::Base.establish_connection(config)
    expect(ActiveRecord::Base.connection).to be_instance_of(ActiveRecord::ConnectionAdapters::MakaraPostgreSQLAdapter)
  end

  it 'should not blow up if a connection fails' do
    config['makara']['connections'].select{|h| h['role'] == 'slave' }.each{|h| h['username'] = 'other'}

    require 'active_record/connection_adapters/postgresql_adapter'

    original_method = ActiveRecord::Base.method(:postgresql_connection)

    allow(ActiveRecord::Base).to receive(:postgresql_connection) do |config|
      if config[:username] == 'other'
        raise "could not connect"
      else
        original_method.call(config)
      end
    end

    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.connection
  end

  context 'with the connection established and schema loaded' do

    before do
      load(File.dirname(__FILE__) + '/../../support/schema.rb')
      ActiveRecord::Base.establish_connection(config)
    end

    let(:connection) { ActiveRecord::Base.connection }

    it 'should have one master and two slaves' do
      expect(connection.master_pool.connection_count).to eq(1)
      expect(connection.slave_pool.connection_count).to eq(2)
    end

    it 'should allow real queries to work' do
      connection.execute('INSERT INTO users (name) VALUES (\'John\')')

      connection.master_pool.connections.each do |master|
        expect(master).to receive(:execute).never
      end

      Makara::Context.set_current Makara::Context.generate
      res = connection.execute('SELECT name FROM users ORDER BY id DESC LIMIT 1')

      expect(res.to_a[0]['name']).to eq('John')
    end

    it 'should send SET operations to each connection' do
      connection.master_pool.connections.each do |con|
        expect(con).to receive(:execute).with("SET TimeZone = 'UTC'").once
      end

      connection.slave_pool.connections.each do |con|
        expect(con).to receive(:execute).with("SET TimeZone = 'UTC'").once
      end
      connection.execute("SET TimeZone = 'UTC'")
    end

    it 'should send reads to the slave' do
      con = connection.slave_pool.connections.first
      expect(con).to receive(:execute).with('SELECT * FROM users').once

      connection.execute('SELECT * FROM users')
    end

    it 'should send writes to master' do
      con = connection.master_pool.connections.first
      expect(con).to receive(:execute).with('UPDATE users SET name = "bob" WHERE id = 1')
      connection.execute('UPDATE users SET name = "bob" WHERE id = 1')
    end

  end

end
