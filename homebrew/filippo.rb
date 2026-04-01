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
      system "bash", "../../scripts/build_macos_app_bundle.sh",
             ".build/release/MenuBarManager",
             buildpath/"Filippo.app",
             version.to_s
    end

    prefix.install buildpath/"Filippo.app"
    bin.install_symlink prefix/"Filippo.app/Contents/MacOS/filippod" => "filippod"

    (libexec/"packages/cli").install Dir["packages/cli/dist"]
    (libexec/"packages/cli").install Dir["packages/cli/node_modules"]
    (libexec/"packages/cli").install "packages/cli/package.json"
    (bin/"filippo").write <<~EOS
      #!/bin/bash
      exec "#{Formula["node"].opt_bin}/node" "#{libexec}/packages/cli/dist/index.js" "$@"
    EOS
  end

  def post_install
    system "/usr/bin/open", "#{opt_prefix}/Filippo.app"
  end

  service do
    run [opt_prefix/"Filippo.app/Contents/MacOS/filippod"]
    keep_alive true
    log_path var/"log/filippo.log"
    error_log_path var/"log/filippo.err"
  end

  def caveats
    <<~EOS
      filippo requires Accessibility permission to manage menu bar icons.
      Start Filippo by opening the app bundle:
        open "#{opt_prefix}/Filippo.app"

      On first launch, Filippo will ask for Accessibility permission
      and whether it should start automatically at login.

      Filippo is installed as:
        #{opt_prefix}/Filippo.app

      To configure which icons are visible:
        filippo configure

      Advanced users can still start the background service manually:
        brew services start filippo

      Config file: ~/.config/filippo/config.toml
    EOS
  end

  test do
    assert_match "MenuBarManager", shell_output("#{bin}/filippod --help 2>&1", 1)
    assert_match "filippo", shell_output("#{bin}/filippo --help")
  end
end
