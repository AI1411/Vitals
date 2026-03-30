class Vitals < Formula
  desc "Ultra-lightweight system resource monitor written in Zig"
  homepage "https://github.com/AI1411/Vitals"
  version "0.1.0"
  license "MIT"

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-aarch64.tar.gz"
      sha256 "PLACEHOLDER_AARCH64_SHA256"
    else
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-x86_64.tar.gz"
      sha256 "PLACEHOLDER_X86_64_SHA256"
    end
  end

  def install
    bin.install "vitals"
  end

  test do
    # --once は /proc が必要なので --help 相当のエラー出力で動作確認
    output = shell_output("#{bin}/vitals --unknown 2>&1", 1)
    assert_match "unknown option", output
  end
end
