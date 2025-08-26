#!/usr/bin/env nu

export def main [] {
  str replace -a '#' '' |
  lines |
  split list -r '-{2,}'
}