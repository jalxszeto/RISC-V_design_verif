"""Reads an Xcelium include list, symlinks each source into WORKSPACE/sym_links,
and writes a path-free include file for compilation."""

import os
import re
import sys

if len(sys.argv) != 2:
    print("Usage: python3 link_files.py <include_file_name>")
    sys.exit(1)

input_file = os.path.join("Include", sys.argv[1])
workspace_dir = "WORKSPACE"
sym_links_dir = os.path.join(workspace_dir, "sym_links")
output_file = os.path.join(sym_links_dir, "sim_no_path.include")

print(f"looking in file {input_file}")
if not os.path.isfile(input_file):
    print(f"Error: include list does not exist: {input_file}")
    sys.exit(1)

os.makedirs(sym_links_dir, exist_ok=True)

had_error = False
seen_links = {}
with open(input_file, "r", encoding="utf-8") as input_fp:
    with open(output_file, "w", encoding="utf-8") as output_fp:
        for raw_line in input_fp:
            line = raw_line.strip()
            if not line or line.startswith("//"):
                output_fp.write(line + "\n")
                continue

            match = re.match(r"^\s*(\S+)\s*$", line)
            if not match:
                print(f"Error: invalid file path in line: {line}")
                had_error = True
                continue

            file_path = os.path.expandvars(match.group(1))
            if not os.path.exists(file_path):
                print(f"Error: file does not exist: {file_path}")
                had_error = True
                continue

            basename = os.path.basename(file_path)
            absolute_path = os.path.abspath(file_path)
            if basename in seen_links and seen_links[basename] != absolute_path:
                print(
                    f"Error: duplicate filename {basename} refers to both "
                    f"{seen_links[basename]} and {absolute_path}"
                )
                had_error = True
                continue
            seen_links[basename] = absolute_path

            link_path = os.path.join(sym_links_dir, basename)
            if os.path.lexists(link_path):
                os.unlink(link_path)
            os.symlink(absolute_path, link_path)

            # Header files are included by cpu_tb_pkg rather than compiled alone.
            if not file_path.endswith(".svh"):
                output_fp.write(f"sym_links/{basename}\n")

if had_error:
    sys.exit(1)
