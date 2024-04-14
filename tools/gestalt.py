#!/usr/bin/env python3

from __future__ import print_function

import argparse
import io
import json
import os
import sys

if sys.version_info[0] >= 3:
    unicode = str

def fatal(msg):
  print(msg, file=sys.stderr)
  sys.exit(1)

def find_files(path):
  for parent, dirs, files in os.walk(path, topdown=True):
    for filename in files:
      if filename == '.' or filename == '~':
        continue
      yield (parent, filename)

def main(arguments):
  parser = argparse.ArgumentParser(description='Describe OpenRCT2 to itself')
  parser.add_argument('-o', dest='output_dir', help='Directory to which the file map will be emitted')
  parser.add_argument('-i', dest='input_dir', help='a directory of swift files')

  args = parser.parse_args(arguments)
  
  if not args.output_dir:
    fatal("output directory is required")

  if not os.path.isdir(args.output_dir):
    os.makedirs(args.output_dir)

  output_path = os.path.join(args.output_dir, 'output.json')

  if not os.path.isdir(args.input_dir):
    fatal("input directory does not exist, or is not a directory")

  openrct_files = find_files(args.input_dir)
  if not openrct_files:
    fatal("no files in the given input directory")

  all_records = {}
  for (root, file) in openrct_files:
    all_records.setdefault(root, []).append(file)

  with io.open(output_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(unicode(json.dumps(all_records, ensure_ascii=False)))

if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))

