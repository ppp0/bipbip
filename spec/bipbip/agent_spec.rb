require 'bipbip'
require 'bipbip/plugin/memcached'
require 'tempfile'

describe Bipbip::Agent do
  let(:agent) { Bipbip::Agent.new }
  let(:plugin) { Bipbip::Plugin::Memcached.new('memcached', {'hostname' => 'localhost', 'port' => 123}, 10) }

  it 'should fail without services' do
    Bipbip.logger = double('logger')

    Bipbip.logger.should_receive(:info).with('Startup...')
    Bipbip.logger.should_receive(:warn).with('No storages configured')

    expect { agent.run }.to raise_error('No services configured')

    Bipbip.logger = nil
  end

  it 'should fork' do
    Bipbip.logger = Logger.new('/dev/null')
    agent.plugins = [plugin]

    plugin.should_receive(:run)

    thread = Thread.new { agent.run }
    sleep 0.5

    thread.alive?.should eq(true)

    Bipbip.logger = nil
  end

  it 'should log plugin errors and retry' do
    logger_file = Tempfile.new('bipbip-mock-logger')
    Bipbip.logger = Logger.new(logger_file.path)

    plugin = Bipbip::Plugin.new('my-plugin', {}, 0.1)
    plugin.stub(:metrics_schema) { [] }
    plugin.stub(:source_identifier) { 'my-source' }
    plugin.stub(:monitor) { raise 'my-error' }

    agent.plugins = [plugin]

    thread = Thread.new { agent.run }
    sleep 0.5

    thread.alive?.should eq(true)
    lines = logger_file.read.lines
    lines.select { |l| l.include?('my-plugin my-source: Error: my-error') }.should have_at_least(2).items

    Bipbip.logger = nil
  end

  it 'should log plugin exceptions' do
    logger_file = Tempfile.new('bipbip-mock-logger')
    Bipbip.logger = Logger.new(logger_file.path)

    plugin = Bipbip::Plugin.new('my-plugin', {}, 0.1)
    plugin.stub(:metrics_schema) { [] }
    plugin.stub(:source_identifier) { 'my-source' }
    plugin.stub(:monitor) { raise Exception.new('my-exception') }

    agent.plugins = [plugin]

    thread = Thread.new do
      $stderr = StringIO.new
      agent.run
    end
    sleep 0.5

    thread.alive?.should eq(true)
    lines = logger_file.read.lines
    lines.select { |l| l.include?('my-plugin my-source: Fatal error: my-exception') }.should have(1).items

    Bipbip.logger = nil
  end

end
