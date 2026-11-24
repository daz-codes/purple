require "test_helper"

class MissionAttempts::Intercepts::FilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @png = "\x89PNG\r\n\x1A\n".b + "pixels".b
    intercepts(:opening).update!(body: nil, file_name: "harbour.png", file_type: "image/png", file_data: @png)
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
    @ref = @attempt.intercept_ref(intercepts(:opening))
  end

  test "the attempt's owner gets the file, a picture inline" do
    sign_in_as users(:one)
    get mission_attempt_intercept_file_path(@attempt, @ref)

    assert_response :success
    assert_equal @png, response.body.b
    assert_equal "image/png", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
  end

  test "anything but a picture downloads" do
    intercepts(:opening).update!(file_name: "rota.pdf", file_type: "application/pdf", file_data: "%PDF-1.4")
    sign_in_as users(:one)
    get mission_attempt_intercept_file_path(@attempt, @ref)

    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
  end

  test "an intercept without a file has nothing to fetch" do
    sign_in_as users(:one)
    get mission_attempt_intercept_file_path(@attempt, @attempt.intercept_ref(intercepts(:wrapped)))
    assert_response :not_found
  end

  test "nobody else can fetch it" do
    sign_in_as users(:two)
    get mission_attempt_intercept_file_path(@attempt, @ref)
    assert_response :not_found
  end
end
