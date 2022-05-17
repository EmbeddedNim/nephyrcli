when not defined(nimscript):
  import system/nimscript

  template before(name, blk: untyped) =
    discard
  template after(name, blk: untyped) =
    discard

import strutils, sequtils, strformat
import tables, json

import os except getEnv, paramCount, paramStr, existsEnv, fileExists, dirExists, findExe

import zconfs

if getEnv("BOARD") == "" and commandLineParams()[^1].startsWith("z"):
  echo "[Nephyr WARNING]: No BOARD variable found. Make sure you source an environment first! "
  echo "\nEnvironments available: "
  for f in listFiles("envs/"):
    echo "\t", "source ", $f

  echo ""
  raise newException(Exception, "Cannot copmpile without board setting")

type
  NimbleArgs = object
    projdir: string
    projname: string
    projsrc: string
    projfile: string
    projbuild: string
    projboard: string
    projflasher: string
    appsrc: string
    args: seq[string]
    child_args: seq[string]
    cachedir: string
    # zephyr_version: string
    app_template: string
    # nephyr_path: string
    debug: bool
    forceclean: bool
    distclean: bool
    help: bool

proc nexec(cmd: string) =
  echo "[nephyrcli] exec: '" & cmd & "'"
  exec(cmd)

proc nRmDir(dir: string) =
  echo "[nephyrcli] remove: '" & dir & "'"
  rmDir(dir)

proc parseNimbleArgs(): NimbleArgs =
  var
    projsrc = "src"
    default_cache_dir = "." / projsrc / "build"
    progfile = thisDir() / projsrc / "main.nim"

  if bin.len() >= 1:
    progfile = bin[0]

  var
    idf_cache_set = false
    override_srcdir = false
    post_idf_args = false
    post_idf_command = false
    idf_args: seq[string] = @[]
    child_args: seq[string] = @[]


  let
    zCommandsBasic = @["zconfigure", "zclean", "zcompile", "zbuild", "zflash"]
    zCommandsBasicBefore = zCommandsBasic.mapIt(it & "before")
    zCommandsBasicAfter = zCommandsBasic.mapIt(it & "after")
    zCommandsOld = @["zephyr_configure", "zephyr_clean", "zephyr_compile", "zephyr_build", "zephyr_flash"]
    zCommands = zCommandsBasic &
                zCommandsBasicBefore & zCommandsBasicAfter &
                zCommandsOld 

  for idx in 0..paramCount():
    # echo fmt"{paramStr(idx)=}"
    if paramStr(idx).toLowerAscii() in zCommands:
      post_idf_command = true
      continue
    if paramStr(idx) == "--":
      post_idf_args = true
      continue
    if paramStr(idx).startsWith("--nimcache"):
      idf_cache_set = true
      continue

    if post_idf_args:
      # setup to find all commands '--' to pass to west
      child_args.add(paramStr(idx))
    elif post_idf_command:
      # setup to find all commands after "zCommands" to pass to our task
      echo fmt"{post_idf_command=}"
      idf_args.add(paramStr(idx))

  child_args = @[] ##\
    # ignore child args for now,
    # need to figure out how to specify which task/child

  if not projsrc.endsWith("src"):
    if override_srcdir:
      echo "  Warning: Zephyr assumes source files will be located in ./src/ folder "
    else:
      echo "  Error: Zephyr assumes source files will be located in ./src/ folder "
      echo "  got source directory: ", projsrc
      quit(1)

  # echo fmt"{idf_args=}"
  # echo fmt"{child_args=}"

  let
    flags = idf_args.filterIt(it.contains(":")).mapIt(it.split(":")).mapIt( (it[0], it[1])).toTable()
    app_template  = flags.getOrDefault("--app-template", "http_server")

  result = NimbleArgs(
    args: idf_args,
    child_args: child_args,
    cachedir: if idf_cache_set: nimCacheDir() else: default_cache_dir,
    projdir: thisDir(),
    projsrc: projsrc,
    appsrc: srcDir,
    projname: projectName(),
    projfile: progfile,
    projboard: getEnv("BOARD"),
    app_template: app_template,
    debug: "--zephyr-debug" in idf_args,
    forceclean: "--clean" in idf_args,
    distclean: "--dist-clean" in idf_args or "--clean-build" in idf_args,
    help: "--help" in idf_args or "-h" in idf_args
  )

  result.projbuild = result.projdir / ("build_" & result.projboard)

  if result.debug: echo "[Got nimble args: ", $result, "]\n"


proc pathCmakeConfig*(buildDir: string,
                      zephyrDir="zephyr",
                      configName=".config"): string =
  var 
    fpath = buildDir / zephyrDir / configName
  echo "[nephyrcli] CMAKE ZCONFG: ", fpath
  return fpath

proc extraArgs(): string =
  result = if existsEnv("NEPHYR_SHIELDS"): "-- -DSHIELD=\"${NEPHYR_SHIELDS}\"" else: ""

task zInstallHeaders, "Install nim headers":
  echo "\n[nephyrcli] Installing nim headers:"
  let
    nopts = parseNimbleArgs()
    cachedir = nopts.cachedir

  if not fileExists(cachedir / "nimbase.h"):
    let nimbasepath = selfExe().splitFile.dir.parentDir / "lib" / "nimbase.h"

    echo("[nephyrcli] ...copying nimbase file into the Nim cache directory ($#)" % [cachedir/"nimbase.h"])
    cpFile(nimbasepath, cachedir / "nimbase.h")
  else:
    echo("[nephyrcli] ...nimbase.h already exists")

task zclean, "Clean nimcache":
  echo "\n[nephyrcli] Cleaning nimcache:"
  let
    nopts = parseNimbleArgs()
    cachedir = nopts.cachedir
  
  if dirExists(cachedir):
    echo fmt"[nephyrcli] ...removing nimcache {cachedir=}"
    nRmDir(cachedir)
  else:
    echo fmt"[nephyrcli] ...cache not found; not removing nimcache {cachedir=}"

  if nopts.forceclean or nopts.distclean:
    echo "[nephyrcli] ...cleaning zephyr build cache"
    nRmDir(nopts.projbuild)

task zconfigure, "Run CMake configuration":
  var nopts = parseNimbleArgs()
  nexec(fmt"west build -p always -b {nopts.projBoard} -d build_{nopts.projBoard} --cmake-only -c {extraArgs()}")

task zcompile, "Compile Nim project for Zephyr program":
  ## compile nim project
  ## 
  var nopts = parseNimbleArgs()
  let zconfpath = pathCmakeConfig(buildDir=nopts.projBuild)

  echo "\n[nephyrcli] Compiling:"

  if not dirExists("src/"):
    echo "\nWarning! The `src/` directory is required but appear appear to exist\n"
    echo "Did you run `nimble zephyr_setup` before trying to compile?\n"

  let
    configs = parseCmakeConfig(zconfpath)
    hasMPU = configs.getOrDefault("CONFIG_MPU", % false).getBool(false)
    hasMMU = configs.getOrDefault("CONFIG_MMU", % false).getBool(false)

    # TODO: FIXME: maybe MMU's as well?
    useMallocFlag =
      if hasMPU or hasMMU: "-d:zephyrUseLibcMalloc"
      else: ""

  let
    nimargs = @[
      "c",
      "--path:" & thisDir() / nopts.appsrc,
      "--nomain",
      "--compileOnly",
      "--nimcache:" & nopts.cachedir.quoteShell(),
      "-d:board:" & nopts.projboard,
      "-d:NimAppMain",
      "" & useMallocFlag, 
      "-d:ZephyrConfigFile:"&zconfpath, # this is important now! sets the config flags
    ].join(" ") 
    childargs = nopts.child_args.mapIt(it.quoteShell()).join(" ")
    compiler_cmd = nimargs & " " & childargs & " " & nopts.projfile.quoteShell() 
  
  echo "compiler_cmd: ", compiler_cmd
  echo "compiler_childargs: ", nopts.child_args

  cd(nopts.projdir)
  selfExec(compiler_cmd)

task zbuild, "Build Zephyr project":
  var nopts = parseNimbleArgs()
  echo "\n[nephyrcli] Building Zephyr/west project:"

  if findExe("west") == "":
    echo "\nError: west not found. Please run the Zephyr export commands: e.g. ` source ~/zephyrproject/zephyr/zephyr-env.sh` and try again.\n"
    quit(2)

  nexec(fmt"west build -p always -b {nopts.projBoard} -d build_{nopts.projBoard} {extraArgs()}")

task zflash, "Flasing Zephyr project":
  var nopts = parseNimbleArgs()
  echo "\n[nephyrcli] Flashing Zephyr/west project:"

  if findExe("west") == "":
    echo "\nError: west not found. Please run the Zephyr export commands: e.g. ` source ~/zephyrproject/zephyr/zephyr-env.sh` and try again.\n"
    quit(2)

  nexec(fmt"west -v flash -d build_{nopts.projBoard} -r {nopts.projflasher} ")


task zsign, "Flasing Zephyr project":
  var nopts = parseNimbleArgs()
  echo "\n[nephyrcli] Flashing Zephyr/west project:"

  if findExe("west") == "":
    echo "\nError: west not found. Please run the Zephyr export commands: e.g. ` source ~/zephyrproject/zephyr/zephyr-env.sh` and try again.\n"
    quit(2)

  # FIXME!!
  nexec("west sign -t imgtool -p ${MCUBOOT}/scripts/imgtool.py -d build_${BOARD} -- --key ${MCUBOOT}/root-rsa-2048.pem")

task zDepsClone, "clone Nephyr deps":
  var nopts = parseNimbleArgs()
  echo fmt"work: {nopts.projDir=}"
  echo fmt"work: {projectPath()=}"
  echo fmt"work: {projectDir()=}"
  echo fmt"work: {getCurrentDir()=}"
  echo fmt"work: {srcDir=}"

  let pkgDir = nopts.projDir & "/../../packages/"
  let devDeps = @["mcu_utils", "fastrpc", "nephyr"]
  var wasCloned: seq[string]
  withDir(pkgDir):
    for dep in devDeps:
      if not dirExists(dep):
        wasCloned.add dep
        echo fmt"[nephyrcli] cloning: {dep}"
        nexec("echo \"MYPWD:\": $(pwd)".fmt)
        nexec(fmt"git clone -v https://github.com/EmbeddedNim/{dep}")
        nexec("echo \"MYDEP:\": $(ls -1 {dep})".fmt)
      else:
        echo fmt"[nephyrcli] not cloning, dir exists: {dep}"

  for dep in devDeps:
    let depPth = pkgDir & dep
    echo(fmt"[nephyrcli] develop: {depPth}")
    nexec(fmt"nimble develop --add:{depPth}")

  if wasCloned.len() > 0:
    zDepsCloneTask()
    try:
      nexec(fmt"nimble sync")
    except OSError:
      echo "Note: nim sync fails on first run"
      echo "Note: running again"
    nexec(fmt"nimble setup")
  nexec(fmt"nimble sync")

task zephyr_configure, "Configure Nephyr project":
  zconfigureTask()

task zephyr_compile, "Compile Nephyr Nim sources":
  zcompileTask()

task zephyr_build, "Build Nephyr/Zephyr firmware":
  zbuildTask()

task zephyr_flash, "Flash Nephyr project":
  zflashTask()

### Actions to ensure correct steps occur before/after certain tasks ###

before zcompile:
  # zDepsCloneTask()
  zCleanTask()
  zConfigureTask()

after zcompile:
  zInstallHeadersTask()

before zbuild:
  # zDepsCloneTask()
  zCleanTask()
  zConfigureTask()
  zCompileTask()
  zInstallHeadersTask()

## TODO: erase me after transition to zbuild, zcompile
before zephyr_compile:
  # zDepsCloneTask()
  zCleanTask()
  zConfigureTask()

after zephyr_compile:
  zInstallHeadersTask()

before zephyr_build:
  # zDepsCloneTask()
  zCleanTask()
  zConfigureTask()
  zCompileTask()
  zInstallHeadersTask()
