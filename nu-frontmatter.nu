#!/usr/bin/env nu
#####################
# This script only works with nushell frontmatter at the moment
#####################


export def main [ file: string ] {
  open $file | lines | split list -r '--== Begin frontmatter ==--' |
   | get 1 | split list -r '--== End frontmatter ==--' | get 0 | str replace -a '#' '' | str trim | split list -r '-{2,}' | get 0
}