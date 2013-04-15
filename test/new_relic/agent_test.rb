# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))
require 'ostruct'

module NewRelic
  # mostly this class just passes through to the active agent
  # through the agent method or the control instance through
  # NewRelic::Control.instance . But it's nice to make sure.
  class MainAgentTest < Test::Unit::TestCase
    include NewRelic::Agent::MethodTracer

    def setup
      NewRelic::Agent.reset_config
    end

    def teardown
      super
      Thread.current[:newrelic_untraced] = nil
    end

    def test_shutdown
      mock_agent = mocked_agent
      mock_agent.expects(:shutdown).with({})
      NewRelic::Agent.shutdown
    end

    def test_shutdown_removes_manual_startup_config
      NewRelic::Agent.manual_start(:some_absurd_setting => true)
      assert NewRelic::Agent.config[:some_absurd_setting]
      NewRelic::Agent.shutdown
      assert !NewRelic::Agent.config[:some_absurd_setting]
    end

    def test_shutdown_removes_server_config
      NewRelic::Agent.manual_start
      NewRelic::Agent.instance.service = default_service
      NewRelic::Agent.instance.finish_setup('agent_config' =>
                                            { :some_absurd_setting => true })
      assert NewRelic::Agent.config[:some_absurd_setting]
      NewRelic::Agent.shutdown
      assert !NewRelic::Agent.config[:some_absurd_setting]
    end

    def test_finish_setup_applied_server_side_config
      with_config({ :'transction_tracer.enabled' => true,
                    'error_collector.enabled' => true,
                    :log_level => 'info' }, :level => 2) do
        NewRelic::Agent.instance.finish_setup('log_level' => 'debug',
         'agent_config' => { 'transaction_tracer.enabled' => false },
                                         'collect_errors' => false)
        assert !NewRelic::Agent.config[:'transaction_tracer.enabled']
        assert !NewRelic::Agent.config[:'error_collector.enabled']
        assert_equal 'debug', NewRelic::Agent.config[:log_level]
      end
    end

    def test_after_fork
      mock_agent = mocked_agent
      mock_agent.expects(:after_fork).with({})
      NewRelic::Agent.after_fork
    end

    if NewRelic::LanguageSupport.can_fork? &&
        !NewRelic::LanguageSupport.using_version?('1.9.1')
      def test_timeslice_harvest_with_after_fork_report_to_channel
        with_config(:agent_enabled => true, :monitor_mode => true) do
          NewRelic::Agent.shutdown # make sure the agent is not already started
          NewRelic::Agent.manual_start(:license_key => ('1234567890' * 4),
                                       :start_channel_listener => true)

          metric = 'Custom/test/method'
          NewRelic::Agent.record_metric(metric, 1.0)

          NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
          NewRelic::Agent.register_report_channel(:agent_test) # before fork
          pid = Process.fork do
            NewRelic::Agent.after_fork(:report_to_channel => :agent_test)
            NewRelic::Agent.record_metric(metric, 2.0)
          end
          Process.wait(pid)
          NewRelic::Agent::PipeChannelManager.listener.stop

          assert_metrics_recorded({
            metric => { :call_count => 2, :total_call_time => 3.0 }
          })
        end
      end
    end

    def test_reset_stats
      mock_agent = mocked_agent
      mock_agent.expects(:reset_stats)
      NewRelic::Agent.reset_stats
    end

    def test_manual_start_default
      mock_control = mocked_control
      mock_control.expects(:init_plugin).with({:agent_enabled => true, :sync_startup => true})
      NewRelic::Agent.manual_start
    end

    def test_manual_start_with_opts
      mock_control = mocked_control
      mock_control.expects(:init_plugin).with({:agent_enabled => true, :sync_startup => false})
      NewRelic::Agent.manual_start(:sync_startup => false)
    end

    def test_manual_start_starts_channel_listener
      NewRelic::Agent::PipeChannelManager.listener.stop
      NewRelic::Agent.manual_start(:start_channel_listener => true)
      assert NewRelic::Agent::PipeChannelManager.listener.started?
      NewRelic::Agent::PipeChannelManager.listener.stop
      NewRelic::Agent.shutdown
    end

    def test_browser_timing_header
      agent = mocked_agent
      agent.expects(:browser_timing_header)
      NewRelic::Agent.browser_timing_header
    end

    def test_browser_timing_footer
      agent = mocked_agent
      agent.expects(:browser_timing_footer)
      NewRelic::Agent.browser_timing_footer
    end

    def test_get_stats
      agent = mocked_agent
      mock_stats_engine = mock('stats_engine')
      agent.expects(:stats_engine).returns(mock_stats_engine)
      mock_stats_engine.expects(:get_stats).with('Custom/test/metric', false)
      NewRelic::Agent.get_stats('Custom/test/metric')
    end

    # note that this is the same as get_stats above, they're just aliases
    def test_get_stats_no_scope
      agent = mocked_agent
      mock_stats_engine = mock('stats_engine')
      agent.expects(:stats_engine).returns(mock_stats_engine)
      mock_stats_engine.expects(:get_stats).with('Custom/test/metric', false)
      NewRelic::Agent.get_stats_no_scope('Custom/test/metric')
    end

    def test_agent_not_started
      old_agent = NewRelic::Agent.agent
      NewRelic::Agent.instance_eval { @agent = nil }
      assert_raise(RuntimeError) do
        NewRelic::Agent.agent
      end
      NewRelic::Agent.instance_eval { @agent = old_agent }
    end

    def test_agent_when_started
      old_agent = NewRelic::Agent.agent
      NewRelic::Agent.instance_eval { @agent = 'not nil' }
      assert_equal('not nil', NewRelic::Agent.agent, "should return the value from @agent")
      NewRelic::Agent.instance_eval { @agent = old_agent }
    end

    def test_abort_transaction_bang
      NewRelic::Agent::Transaction.expects(:abort_transaction!)
      NewRelic::Agent.abort_transaction!
    end

    def test_is_transaction_traced_true
      Thread.current[:record_tt] = true
      assert_equal(true, NewRelic::Agent.is_transaction_traced?, 'should be true since the thread local is set')
    end

    def test_is_transaction_traced_blank
      Thread.current[:record_tt] = nil
      assert_equal(true, NewRelic::Agent.is_transaction_traced?, 'should be true since the thread local is not set')
    end

    def test_is_transaction_traced_false
      Thread.current[:record_tt] = false
      assert_equal(false, NewRelic::Agent.is_transaction_traced?, 'should be false since the thread local is false')
    end

    def test_is_sql_recorded_true
      Thread.current[:record_sql] = true
      assert_equal(true, NewRelic::Agent.is_sql_recorded?, 'should be true since the thread local is set')
    end

    def test_is_sql_recorded_blank
      Thread.current[:record_sql] = nil
      assert_equal(true, NewRelic::Agent.is_sql_recorded?, 'should be true since the thread local is not set')
    end

    def test_is_sql_recorded_false
      Thread.current[:record_sql] = false
      assert_equal(false, NewRelic::Agent.is_sql_recorded?, 'should be false since the thread local is false')
    end

    def test_is_execution_traced_true
      Thread.current[:newrelic_untraced] = [true, true]
      assert_equal(true, NewRelic::Agent.is_execution_traced?, 'should be true since the thread local is set')
    end

    def test_is_execution_traced_blank
      Thread.current[:newrelic_untraced] = nil
      assert_equal(true, NewRelic::Agent.is_execution_traced?, 'should be true since the thread local is not set')
    end

    def test_is_execution_traced_empty
      Thread.current[:newrelic_untraced] = []
      assert_equal(true, NewRelic::Agent.is_execution_traced?, 'should be true since the thread local is an empty array')
    end

    def test_is_execution_traced_false
      Thread.current[:newrelic_untraced] = [true, false]
      assert_equal(false, NewRelic::Agent.is_execution_traced?, 'should be false since the thread local stack has the last element false')
    end

    def test_instance
      assert_equal(NewRelic::Agent.agent, NewRelic::Agent.instance, "should return the same agent for both identical methods")
    end

    def test_register_report_channel
      NewRelic::Agent.register_report_channel(:channel_id)
      assert NewRelic::Agent::PipeChannelManager.channels[:channel_id] \
        .kind_of?(NewRelic::Agent::PipeChannelManager::Pipe)
      NewRelic::Agent::PipeChannelManager.listener.close_all_pipes
    end

    def test_record_metric
      dummy_engine = NewRelic::Agent.agent.stats_engine
      dummy_engine.expects(:record_metrics).with('foo', 12)
      NewRelic::Agent.record_metric('foo', 12)
    end

    def test_record_metric_accepts_hash
      dummy_engine = NewRelic::Agent.agent.stats_engine
      stats_hash = {
        :count => 12,
        :total => 42,
        :min   => 1,
        :max   => 5,
        :sum_of_squares => 999
      }
      expected_stats = NewRelic::Agent::Stats.new()
      expected_stats.call_count = 12
      expected_stats.total_call_time = 42
      expected_stats.total_exclusive_time = 42
      expected_stats.min_call_time = 1
      expected_stats.max_call_time = 5
      expected_stats.sum_of_squares = 999
      dummy_engine.expects(:record_metrics).with('foo', expected_stats)
      NewRelic::Agent.record_metric('foo', stats_hash)
    end

    def test_increment_metric
      dummy_engine = NewRelic::Agent.agent.stats_engine
      dummy_stats = mock
      dummy_stats.expects(:increment_count).with(12)
      dummy_engine.expects(:record_metrics).with('foo').yields(dummy_stats)
      NewRelic::Agent.increment_metric('foo', 12)
    end

    class Transactor
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      def txn
        yield
      end
      add_transaction_tracer :txn

      def task_txn
        yield
      end
      add_transaction_tracer :task_txn, :category => :task
    end

    def test_set_transaction_name
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset_stats
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert engine.lookup_stats('Controller/new_name')
    end

    def test_set_transaction_name_applies_proper_scopes
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset_stats
      Transactor.new.txn do
        trace_execution_scoped('Custom/something') {}
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert engine.lookup_stats('Custom/something', 'Controller/new_name')
    end

    def test_set_transaction_name_sets_tt_name
      sampler = NewRelic::Agent.instance.transaction_sampler
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert_equal 'Controller/new_name', sampler.last_sample.params[:path]
    end

    def test_set_transaction_name_gracefully_fails_when_frozen
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset_stats
      Transactor.new.txn do
        NewRelic::Agent::Transaction.current.freeze_name
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert_nil engine.lookup_stats('Controller/new_name')
    end

    def test_set_transaction_name_applies_category
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset_stats
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name', :category => :task)
      end
      assert engine.lookup_stats('OtherTransaction/Background/new_name')
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name', :category => :rack)
      end
      assert engine.lookup_stats('Controller/Rack/new_name')
      Transactor.new.txn do
        NewRelic::Agent.set_transaction_name('new_name', :category => :sinatra)
      end
      assert engine.lookup_stats('Controller/Sinatra/new_name')
    end

    def test_set_transaction_name_uses_current_txn_category_default
      engine = NewRelic::Agent.instance.stats_engine
      engine.reset_stats
      Transactor.new.task_txn do
        NewRelic::Agent.set_transaction_name('new_name')
      end
      assert engine.lookup_stats('OtherTransaction/Background/new_name')
    end

    private

    def mocked_agent
      agent = mock('agent')
      NewRelic::Agent.stubs(:agent).returns(agent)
      agent
    end

    def mocked_control
      server = NewRelic::Control::Server.new('localhost', 3000)
      control = OpenStruct.new(:license_key => 'abcdef',
                               :server => server)
      control.instance_eval do
        def [](key)
          nil
        end

        def fetch(k,d)
          nil
        end
      end

      NewRelic::Control.stubs(:instance).returns(control)
      control
    end
  end
end
