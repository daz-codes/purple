require "test_helper"

class ErrorAlertTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @alert = ErrorAlert.new(to: "team@purple.example", cache: @cache)
  end

  test "emails the error class, message and app backtrace, but no context values" do
    assert_emails 1 do
      report raised(RuntimeError, "the inbox fell over"), context: { user_email: "player@purple.example" }
    end

    email = ActionMailer::Base.deliveries.last
    assert_equal [ "team@purple.example" ], email.to
    assert_equal "[Purple] RuntimeError: the inbox fell over", email.subject
    body = email.body.to_s
    assert_includes body, "RuntimeError: the inbox fell over"
    assert_includes body, "test/models/error_alert_test.rb"
    assert_includes body, "Context: user_email"
    assert_not_includes body, "player@purple.example"
  end

  test "the same error alerts once an hour, a different one alerts straight away" do
    error = raised(RuntimeError, "boom")

    assert_emails 1 do
      3.times { report error }
    end
    assert_emails 1 do
      report raised(ArgumentError, "different")
    end

    travel ErrorAlert::QUIET_FOR + 1.minute do
      assert_emails 1 do
        report error
      end
    end
  end

  test "warnings and info don't alert" do
    assert_no_emails do
      report raised(RuntimeError, "meh"), severity: :warning
      report raised(RuntimeError, "fyi"), severity: :info
    end
  end

  test "does nothing without a recipient" do
    assert_no_emails do
      ErrorAlert.new(to: nil, cache: @cache).report(raised(RuntimeError, "x"), handled: false, severity: :error, context: {})
    end
  end

  test "never raises, even when alerting itself fails" do
    broken_cache = Class.new { def write(*, **) = raise(Errno::ECONNREFUSED) }.new
    alert = ErrorAlert.new(to: "team@purple.example", cache: broken_cache)

    assert_nothing_raised do
      alert.report(raised(RuntimeError, "boom"), handled: false, severity: :error, context: {})
    end
  end

  private
    def report(error, severity: :error, context: {})
      @alert.report(error, handled: false, severity:, context:, source: "application.action_dispatch")
    end

    def raised(klass, message)
      raise klass, message
    rescue klass => error
      error
    end
end
