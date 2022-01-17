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

proc unTarball(pkgcache, name, pkg: string, folder: (string, string)) =
  echo "unTarball: ", name, " tar: ", pkg, " => ", folder
  let pkgdir = pkgcache / name
  pkgdir.createDir()
  let cmd = fmt"tar -C {pkgdir} -xf {pkg} "
  echo "tar command: ", cmd
  let res = execShellCmd(cmd)
  if res != 0:
    raise newException(ValueError, fmt"couldn't create tarball: {pkg}")


proc unFreezeModules(manifest, outdir: string) =
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
    outdir.unTarball(name, pkg=pkg, folder=path.splitPath())

proc setupZephyrWest(zdir: string) =
  let cd = getCurrentDir()
  setCurrentDir(zdir)
  assert 0 == execShellCmd("west init -l")
  assert 0 == execShellCmd("west update --name-cache $PWD/../pkgs-cache/")
  cd.setCurrentDir()

when isMainModule:
  if not existsDir("zephyr"):
    createDir("zephyr")
    let res = execShellCmd("tar xf ~/.nephyr/zephyr-v2.7.1.tar.gz --strip-components 1 -C zephyr")
    assert res == 0

  let zephyrdir = "zephyr/"
  unFreezeModules(manifest=zephyrdir/"west.yml", outdir="pkgs-cache/")
  zephyrdir.setupZephyrWest()

  removeDir("pkgs-cache/")

# for t in *.tar.bz2; do echo "t: " $t; tar xvf $t; done