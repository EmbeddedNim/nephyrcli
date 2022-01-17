import std/os, std/strformat, std/sequtils, std/sugar, std/tables
import zippy/tarballs
import regex

import json
import yaml
import yaml/tojson

iterator findModules(name: Regex): string =
  for dir in walkDirRec(".", {pcDir}, {pcDir}, relative=true):
    if dir.splitPath()[1].match(name):
      yield dir

proc mkTarball(name, pkg: string, folder: (string, string)) =
  echo "mkTarball: ", name, " tar: ", pkg, " => ", folder
  let cmd = fmt"tar -C {folder[0] / folder[1]} -cf {pkg} ./"
  echo "tar command: ", cmd
  let res = execShellCmd(cmd)
  if res != 0:
    raise newException(ValueError, fmt"couldn't create tarball: {pkg}")


proc freezeModules(manifest, outdir: string) =
  var modules = newTable[string, (string, string)]()

  let westNode = loadToJson(readFile(manifest))[0]
  let projs = westNode["manifest"]["projects"]
  for proj in projs.items():
    let
      name = proj["name"].getStr
      rev = proj["revision"].getStr
      path = proj["path"].getStr
      pkg = "pkgs" / fmt"{name}.{rev}.tar.gz"
    echo "info: ", proj
    modules[fmt"{name}"] = (pkg, path)

  createDir(outdir)
  for name, (pkg, path) in modules:
    mkTarball(name, pkg=pkg, folder=path.splitPath())

when isMainModule:
  freezeModules(manifest="zephyr/west.yml", outdir="pkgs/")

# for t in *.tar.bz2; do echo "t: " $t; tar xvf $t; done