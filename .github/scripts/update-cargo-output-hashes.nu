#!/usr/bin/env nix-shell
#! nix-shell -i nu -p nushell

let flake_file = "flake.nix"
let build_target = ".#plank"
let fake_hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
let max_rounds = 20


def run-python [lines: list<string>, args: list<string>] {
  let script = (^mktemp | str trim)
  $lines | str join (char nl) | save --raw --force $script
  ^python3 $script ...$args
  rm $script
}


def upsert-hash [file: string, dep: string, hash: string] {
  let code = [
    "import pathlib, sys"
    "file, dep, hash = sys.argv[1:4]"
    "path = pathlib.Path(file)"
    "lines = path.read_text().splitlines()"
    "out = []"
    "in_block = False"
    "replaced = False"
    "entry = f'              \"{dep}\" = \"{hash}\";'"
    "needle = f'\"{dep}\" ='"
    "for line in lines:"
    "    trimmed = line.strip()"
    "    if trimmed == 'outputHashes = {':"
    "        out.append(line)"
    "        in_block = True"
    "        continue"
    "    if in_block and trimmed == '};':"
    "        if not replaced:"
    "            out.append(entry)"
    "        out.append(line)"
    "        in_block = False"
    "        continue"
    "    if in_block and trimmed.startswith(needle):"
    "        out.append(entry)"
    "        replaced = True"
    "        continue"
    "    out.append(line)"
    "path.write_text('\\n'.join(out) + '\\n')"
  ]
  run-python $code [$file $dep $hash]
}


def remove-hash [file: string, dep: string] {
  let code = [
    "import pathlib, sys"
    "file, dep = sys.argv[1:3]"
    "path = pathlib.Path(file)"
    "lines = path.read_text().splitlines()"
    "out = []"
    "in_block = False"
    "needle = f'\"{dep}\" ='"
    "for line in lines:"
    "    trimmed = line.strip()"
    "    if trimmed == 'outputHashes = {':"
    "        out.append(line)"
    "        in_block = True"
    "        continue"
    "    if in_block and trimmed == '};':"
    "        out.append(line)"
    "        in_block = False"
    "        continue"
    "    if in_block and trimmed.startswith(needle):"
    "        continue"
    "    out.append(line)"
    "path.write_text('\\n'.join(out) + '\\n')"
  ]
  run-python $code [$file $dep]
}


mut round = 0
print ("cargo hash fixer: start target=" + $build_target + " max_rounds=" + ($max_rounds | into string))
loop {
  $round += 1
  if $round > $max_rounds {
    error make {
      msg: $'gave up after ($max_rounds) rounds fixing cargo output hashes'
    }
  }

  print ("cargo hash fixer: round " + ($round | into string) + " build")
  let result = (do -i { ^nix build $build_target --no-link --print-build-logs | complete })

  if $result.exit_code == 0 {
    print ("cargo hash fixer: round " + ($round | into string) + " clean")
    break
  }

  let output = $'($result.stdout)
($result.stderr)'
  print ("cargo hash fixer: round " + ($round | into string) + " failed")
  print $output

  let missing = ($output | parse -r 'No hash was found while vendoring the git dependency (?<dep>.+?)\.' )
  if not ($missing | is-empty) {
    let dep = ($missing | get dep | first)
    print ("cargo hash fixer: add fake hash for missing git dep " + $dep)
    upsert-hash $flake_file $dep $fake_hash
    continue
  }

  let stale = ($output | parse -r 'A hash was specified for (?<dep>[^,]+), but there is no corresponding git dependency\.')
  if not ($stale | is-empty) {
    let dep = ($stale | get dep | first)
    print ("cargo hash fixer: remove stale hash for " + $dep)
    remove-hash $flake_file $dep
    continue
  }

  let mismatch = ($output | parse -r "Cannot build '/nix/store/[0-9a-z]{32}-(?<dep>.+)\\.drv'")
  let got_hash = ($output | parse -r 'got:\s+(?<hash>sha256-[A-Za-z0-9+/=]+)')

  if (not ($mismatch | is-empty)) and (not ($got_hash | is-empty)) {
    let dep = ($mismatch | get dep | first)
    let hash = ($got_hash | get hash | first)
    print ("cargo hash fixer: update " + $dep + " -> " + $hash)
    upsert-hash $flake_file $dep $hash
    continue
  }

  error make {
    msg: $'could not extract cargo output hash from build failure'
  }
}
print "cargo hash fixer: done"
