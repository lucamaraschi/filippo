class Filippo < Formula
  desc "Declarative, config-driven menu bar icon manager for macOS"
  homepage "https://github.com/lucamaraschi/filippo"
  url "__URL__"
  sha256 "__SHA256__"
  license "MIT"

  depends_on :macos
  depends_on "node"
  depends_on xcode: ["15.0", :build]

  def install
    cd "app/MenuBarManager" do
      system "swift", "build",
             "-c", "release",
             "--disable-sandbox"
      bin.install ".build/release/MenuBarManager" => "filippod"
    end

    (libexec/"packages/cli").install Dir["packages/cli/dist"]
    (libexec/"packages/cli").install Dir["packages/cli/node_modules"]
    (libexec/"packages/cli").install "packages/cli/package.json"
    (bin/"filippo").write <<~EOS
      #!/bin/bash
      exec "#{Formula["node"].opt_bin}/node" "#{libexec}/packages/cli/dist/index.js" "$@"
    EOS
  end

  service do
    run opt_bin/"filippod"
    keep_alive true
    log_path var/"log/filippo.log"
    error_log_path var/"log/filippo.err"
  end

  def caveats
    <<~EOS
      filippo requires Accessibility permission to manage menu bar icons.
      Start the daemon once so macOS can register it for permission prompts:
        brew services start filippo

      To configure which icons are visible:
        filippo configure

      Config file: ~/.config/filippo/config.toml
    EOS
  end

  test do
    assert_match "MenuBarManager", shell_output("#{bin}/filippod --help 2>&1", 1)
    assert_match "filippo", shell_output("#{bin}/filippo --help")
  end
end
