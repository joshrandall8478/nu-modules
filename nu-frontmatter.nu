#!/usr/bin/env nu
#####################
# This script only works with nushell frontmatter at the moment
#####################


export def main [ file: string ] {
  # let found = split list -r '--== (?<name>.*) ==--'
  # $found.name
  # PCRE
  open $file
  | lines
  | split list -r '--== (?i)Begin frontmatter ==--'
  | get 1
  | split list -r '--== (?i)End frontmatter ==--'
  | get 0
  | str replace --regex '^(#|\/\/) ' ''
  | to text
  | from yaml
  # | save test.yml --force
  # | str trim
  # | split list -r '-{2,}'
  # | get 0
}