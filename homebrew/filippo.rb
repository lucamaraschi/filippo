class Filippo < Formula
  desc "Declarative, config-driven menu bar icon manager for macOS"
  homepage "https://github.com/lucamaraschi/filippo"
  url "https://github.com/lucamaraschi/filippo/archive/refs/tags/v__VERSION__.tar.gz"
  sha256 "__SHA256__"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    cd "app/MenuBarManager" do
      system "swift", "build",
             "-c", "release",
             "--disable-sandbox"
      bin.install ".build/release/MenuBarManager" => "filippod"
    end
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
      On first launch, you'll be prompted to grant this in System Settings.

      To start filippo now and auto-start on login:
        brew services start filippo

      To configure which icons are visible:
        npx @filippo/cli configure

      Or install the CLI globally:
        npm install -g @filippo/cli
        filippo configure

      Config file: ~/.config/filippo/config.toml
    EOS
  end

  test do
    assert_match "MenuBarManager", shell_output("#{bin}/filippod --help 2>&1", 1)
  end
end
