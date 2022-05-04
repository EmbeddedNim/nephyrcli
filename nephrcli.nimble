# Package

version       = "0.1.10"
author        = "Jaremy Creechley"
description   = "nephyr cli utils"
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
binDir        = "bin"
bin           = @["nephrcli", "nfreeze", "nunfreeze"]


# Dependencies

requires "nim >= 1.6.2"
requires "regex"
requires "zippy"
requires "yaml"
