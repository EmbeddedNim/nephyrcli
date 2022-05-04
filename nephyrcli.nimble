# Package

version       = "0.2.31"
author        = "Jaremy Creechley"
description   = "nephyr cli utils"
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
binDir        = "bin"
bin           = @["nephyrcli", "nephyrclipkg/cli/nfreeze", "nephyrclipkg/cli/nunfreeze"]
skipDirs = @["nephyrcli"]


# Dependencies

requires "nim >= 1.6.2"
requires "regex"
requires "zippy"
requires "yaml"
