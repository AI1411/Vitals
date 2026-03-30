class Vitals < Formula
  desc "Ultra-lightweight system resource monitor written in Zig"
  homepage "https://github.com/AI1411/Vitals"
  version "1.0.5"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-macos-aarch64.tar.gz"
      sha256 "14f7bda85a0f963ad03fe4bf658ea09a121326aa7685e796c5516fb256277cdb"
    else
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-macos-x86_64.tar.gz"
      sha256 "4c607f2c7622c5b58d2950679fc24361239d83b852f4d312ccf05d5f947ed574"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-aarch64.tar.gz"
      sha256 "a80816b01d59804666322aa0a15b61da93d6f36c3f04e02f02f4acc652bda2a2"
    else
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-x86_64.tar.gz"
      sha256 "aeac0c6cc50cdd5e53f956020c14d42f007fbb2077cf0ab68c3832e3859b5bcb"
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
