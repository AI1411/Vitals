class Vitals < Formula
  desc "Ultra-lightweight system resource monitor written in Zig"
  homepage "https://github.com/AI1411/Vitals"
  version "1.0.4"
  license "MIT"

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-aarch64.tar.gz"
      sha256 "23fe5c3161263074fdefdfe7300add658017c7ba8a53b132dfe20ec5f89ce491"
    else
      url "https://github.com/AI1411/Vitals/releases/download/v#{version}/vitals-linux-x86_64.tar.gz"
      sha256 "fd8f440d446b7e53453f761dbc779926dc8ead58128283d6434499abeeaa60ec"
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
