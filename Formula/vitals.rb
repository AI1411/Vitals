class Vitals < Formula
  desc "Ultra-lightweight system resource monitor written in Zig"
  homepage "https://github.com/AI1411/Vitals"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-macos-aarch64.tar.gz"
      sha256 "PLACEHOLDER_MACOS_AARCH64_SHA256"
    else
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-macos-x86_64.tar.gz"
      sha256 "PLACEHOLDER_MACOS_X86_64_SHA256"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-aarch64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_AARCH64_SHA256"
    else
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-x86_64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_X86_64_SHA256"
    end
  end

  def install
    bin.install "vitals"
  end

  test do
    output = shell_output("#{bin}/vitals --unknown 2>&1", 1)
    assert_match "unknown option", output
  end
end
