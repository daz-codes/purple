require "application_system_test_case"

class SignalsTest < ApplicationSystemTestCase
  test "a player decodes intercepts in the Workbench, submits flags, and the next track opens" do
    sign_in users(:one)
    visit paths_path
    within("section#codebreaking") { assert_text "Finish 1 more mission on Encodings to open this track." }

    visit mission_path(missions(:kettle))
    click_on "Start mission"
    assert_selector "#mission_intercept h2", text: "Opening call"
    html = page.html
    [ intercepts(:opening), intercepts(:wrapped) ].each do |intercept|
      [ intercept.key, intercept.solution, intercept.explanation, *intercept.flag_digests ].each { |secret| assert_not_includes html, secret }
    end
    assert_accessible

    # One step: From Base64.
    click_on "Load into the Workbench"
    add_step "From Base64"
    assert_selector "[data-testid=workbench-output]", text: "TEAPOT CALLS THE BASE THE BISCUIT TIN."

    submit_flag "the teapot"
    assert_selector "#mission_notice", text: "Not that. 4 tries left on this intercept."
    submit_flag "Biscuit tin"
    assert_selector "#mission_notice", text: "Flag found."
    assert_selector "[data-testid=flag-found]", text: "Biscuit tin"

    # The Workbench keeps its recipe when switching intercepts; this one needs a second step.
    within("#mission_intercepts") { click_on "Wrapped twice" }
    assert_selector "#mission_intercept h2", text: "Wrapped twice"
    assert_selector "[data-testid=workbench-step]", count: 1
    click_on "Load into the Workbench"
    add_step "From Base64"
    assert_selector "[data-testid=workbench-output]", text: "Meet at the Old Lighthouse at 0340."
    assert_accessible

    submit_flag "old lighthouse"
    assert_selector "[data-testid=flags-found]", text: "2"
    assert_selector "[data-testid=debrief-headline]", text: "You found 2 of 2 flags and made 1 wrong guess."
    assert_selector "[data-testid=debrief-solution]", text: "Meet at the Old Lighthouse at 0340."
    assert_text "In the Workbench: From Base64, then From Base64."
    assert_accessible

    visit paths_path
    within("section#codebreaking") { assert_no_text "Finish 1 more mission" }
    click_on "Ciphers"
    assert_no_selector "[data-testid=locked]"
  end

  test "a step that can't run says why, and steps after it wait" do
    sign_in users(:one)
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:tea_for_two).tap { |mission| mission.update!(track: tracks(:encodings)) })
    visit mission_attempt_path(attempt)

    fill_in "Input", with: "not base64!"
    add_step "From Base64"
    add_step "Reverse"
    steps = all("[data-testid=workbench-step]")
    within(steps[0]) { assert_text "That isn't valid Base64." }
    within(steps[1]) { assert_text "Waiting for the step above." }

    within(steps[0]) { click_on "Remove" }
    assert_selector "[data-testid=workbench-output]", text: "!46esab ton"
  end

  test "an intercept that looks like a number or JSON loads into the Workbench exactly as shown" do
    sign_in users(:one)
    hex = Intercept::Cipher.new(%w[ to_hex ]).encode("Ship at 0340")
    assert_match(/\A\d+\z/, hex)
    intercepts(:opening).update!(body: hex, recipe: %w[ to_hex ], title: "1234")
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
    visit mission_attempt_path(attempt)

    click_on "Load into the Workbench"
    assert_field "Input", with: hex
    assert_text "Loaded: 1234"
    add_step "From hex"
    assert_selector "[data-testid=workbench-output]", text: "Ship at 0340"

    intercepts(:opening).update!(body: '[{"to":"TEAPOT"}]', title: "true")
    visit mission_attempt_path(attempt)
    click_on "Load into the Workbench"
    assert_field "Input", with: '[{"to":"TEAPOT"}]'
    assert_text "Loaded: true"
  end

  test "URL decoding gives back raw bytes, so a high-byte XOR then URL-encoding decodes in the browser" do
    sign_in users(:one)
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
    visit mission_attempt_path(attempt)
    assert_selector "[data-testid=workbench]"

    cipher = Intercept::Cipher.new([ { "xor_hex" => "F00D" }, "url_encode" ])
    body = cipher.encode("Meet at the Old Lighthouse at 0340.")
    assert_match(/%[89A-F]/, body)
    cases = [
      { body:, steps: cipher.undo_steps, solution: "Meet at the Old Lighthouse at 0340." },
      { body: "50%+off%zz", steps: [ [ "url_decode" ] ], solution: CGI.unescape("50%+off%zz") }
    ]
    failures = run_operations(<<~JS, cases)
      const results = []
      for (const { body, steps, solution } of cases) {
        let bytes = ops.bytesFromText(body)
        for (const [name, argument] of steps) bytes = (await ops.OPERATIONS[name](bytes, argument)).bytes
        const decoded = ops.textFromBytes(bytes)
        if (decoded !== solution) results.push(`${body}: ${decoded}`)
      }
      return results
    JS
    assert_empty failures
  end

  test "every shipped intercept decodes in the browser exactly as the importer encoded it" do
    Content::Import.new.run
    sign_in users(:one)
    mission = Mission.find_by!(slug: "kettle-chatter")
    attempt = MissionAttempt.start(user: users(:one), mission:)
    visit mission_attempt_path(attempt)
    assert_selector "[data-testid=workbench]"

    encoded = Intercept.includes(:mission).select { |intercept| intercept.recipe.present? }
    text = encoded.map do |intercept|
      { key: intercept.key, body: intercept.body, steps: intercept.undo_steps, solution: intercept.solution }
    end
    failures = run_operations(<<~JS, text)
      const results = []
      for (const { key, body, steps, solution } of cases) {
        let bytes = ops.bytesFromText(body)
        for (const [name, argument] of steps) bytes = (await ops.OPERATIONS[name](bytes, argument)).bytes
        const decoded = ops.textFromBytes(bytes)
        if (decoded !== solution) results.push(`${key}: ${decoded}`)
      }
      return results
    JS
    codebreaking = Mission.joins(track: :path).where(paths: { slug: "codebreaking" })
    assert_equal codebreaking.pluck(:slug).sort, encoded.map { |intercept| intercept.mission.slug }.uniq.sort
    assert_empty failures
  end

  test "the Forensics files give up their flags to the Workbench's file steps" do
    Content::Import.new.run
    sign_in users(:one)
    files = Intercept.where.not(file_data: nil).index_by(&:key)
    attempts = files.values.map(&:mission).uniq.index_with { |mission| MissionAttempt.start(user: users(:one), mission:) }
    visit mission_attempt_path(attempts.values.first)
    assert_selector "[data-testid=workbench]"

    url = ->(key) { mission_attempt_intercept_file_path(attempts[files[key].mission], attempts[files[key].mission].intercept_ref(files[key])) }
    cases = [
      { url: url.("photographer"), steps: [ [ "metadata" ] ], expect: "Artist: Lt. Ottilie Brack, Grizzlemark Signals" },
      { url: url.("photographer"), steps: [ [ "metadata" ] ], expect: "GPS latitude: 61.48213° N" },
      { url: url.("photographer"), steps: [ [ "metadata" ] ], expect: "GPS longitude: 23.17459° W" },
      { url: url.("photo_recipient"), steps: [ [ "metadata" ] ], expect: "Comment: Send to Major Fitch by Tuesday." },
      { url: url.("rota_author"), steps: [ [ "metadata" ] ], expect: "Author: Sgt. Wilbur Cragg" },
      { url: url.("rota_software"), steps: [ [ "metadata" ] ], expect: "Creator: Grizzlemark Office Suite" },
      { url: url.("drop_point"), steps: [ [ "strings" ] ], expect: "TEAPOT: leave the printed copy in the old boathouse." },
      { url: url.("dog_name"), steps: [ [ "lsb" ] ], expect: "TEAPOT: the sentry dog is called Biscuit. Bring ham." },
      { url: url.("fallback_frequency"), steps: [ [ "strings" ] ], expect: "TEAPOT FALLBACK FREQUENCY 4.625 MHz." },
      { url: url.("pickup_time"), steps: [ [ "lsb" ], [ "from_base64" ] ], expect: "Boat pickup at 0215 from the shingle beach." },
      { url: url.("smuggled_text"), steps: [ [ "find_all", '([0-9a-f]+)\.\d+\.kettle' ], [ "from_hex" ] ],
        expect: "Sunday nights have only two guards at the fuel depot." }
    ]
    failures = run_operations(<<~JS, cases)
      const results = []
      for (const { url, steps, expect } of cases) {
        let bytes = new Uint8Array(await (await fetch(url)).arrayBuffer())
        for (const [name, argument] of steps) bytes = (await ops.OPERATIONS[name](bytes, argument)).bytes
        const output = ops.textFromBytes(bytes)
        if (!output.includes(expect)) results.push(`${url} ${JSON.stringify(steps)}: ${output}`)
      }
      return results
    JS
    assert_empty failures
  end

  private
    def add_step(label)
      select label, from: "Add a step"
      click_on "Add step"
    end

    def submit_flag(answer)
      fill_in "Your answer (the flag)", with: answer
      click_on "Submit flag"
    end

    # Runs the Workbench's own operations module in the page against cases, with ops and cases in scope.
    def run_operations(body, cases)
      page.evaluate_async_script(<<~JS, cases.to_json)
        const done = arguments[arguments.length - 1]
        const cases = JSON.parse(arguments[0])
        import("workbench/operations").then(async (ops) => {
          try { done(await (async () => { #{body} })()) } catch (error) { done([`error: ${error.message}`]) }
        })
      JS
    end
end
