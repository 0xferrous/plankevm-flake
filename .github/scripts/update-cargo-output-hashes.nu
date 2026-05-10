#!/usr/bin/env nix-shell
#! nix-shell -i nu -p nushell

let flake_file = "flake.nix"
let build_target = ".#plank"
let fake_hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
let max_rounds = 20


def run-python [lines: list<string>, args: list<string>] {
  let script = (^mktemp | str trim)
  $lines | str join (char nl) | save --raw --force $script
  let result = (^python3 $script ...$args)
  rm $script
  $result
}


def extract-regex-group [text: string, pattern: string, group: string] {
  let input = (^mktemp | str trim)
  $text | save --raw --force $input
  let code = [
    "import pathlib, re, sys"
    "path, pattern, group = sys.argv[1:4]"
    "text = pathlib.Path(path).read_text()"
    "text = re.sub(r'\\x1b\\[[0-9;]*m', '', text)"
    "idx = int(group)"
    "match = None"
    "for line in text.splitlines():"
    "    match = re.search(pattern, line.strip())"
    "    if match:"
    "        break"
    "print(match.group(idx) if match else '')"
  ]
  let result = (run-python $code [$input $pattern $group] | str trim)
  rm $input
  $result
}


def upsert-hash [file: string, dep: string, hash: string] {
  let code = [
    "import pathlib, sys"
    "file, dep, hash = sys.argv[1:4]"
    "path = pathlib.Path(file)"
    "lines = path.read_text().splitlines()"
    "out = []"
    "in_block = False"
    "has_block = any(line.strip() == 'outputHashes = {' for line in lines)"
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
    "    if (not has_block) and trimmed == 'lockFile = plank-monorepo + \"/plankc/Cargo.lock\";':"
    "        out.append(line)"
    "        out.append('            outputHashes = {')"
    "        out.append(entry)"
    "        out.append('            };')"
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

  let missing_dep = (extract-regex-group $output 'error: No hash was found while vendoring the git dependency (.+)\.' '1')
  if $missing_dep != "" {
    print ("cargo hash fixer: add fake hash for missing git dep " + $missing_dep)
    upsert-hash $flake_file $missing_dep $fake_hash
    continue
  }

  let stale_dep = (extract-regex-group $output 'error: A hash was specified for ([^,]+), but there is no corresponding git dependency\.' '1')
  if $stale_dep != "" {
    print ("cargo hash fixer: remove stale hash for " + $stale_dep)
    remove-hash $flake_file $stale_dep
    continue
  }

  let mismatch_dep = (extract-regex-group $output "Cannot build '/nix/store/[0-9a-z]{32}-(.+)\\.drv'" '1')
  let got_hash = (extract-regex-group $output 'got:\s+(sha256-[A-Za-z0-9+/=]+)' '1')

  if $mismatch_dep != "" and $got_hash != "" {
    print ("cargo hash fixer: update " + $mismatch_dep + " -> " + $got_hash)
    upsert-hash $flake_file $mismatch_dep $got_hash
    continue
  }

  error make {
    msg: $'could not extract cargo output hash from build failure'
  }
}
print "cargo hash fixer: done"
