"""LLVM lit test configuration for XttSFPU extension tests."""

import os
import lit.formats

config.name = "XttSFPU"
config.test_format = lit.formats.ShTest(True)
config.suffixes = ['.s', '.ll']
config.test_source_root = os.path.dirname(__file__)

# Find build directory
build_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'build')
config.substitutions.append(('%llvm-mc',
    os.path.join(build_dir, 'bin', 'llvm-mc')))
config.substitutions.append(('%llc',
    os.path.join(build_dir, 'bin', 'llc')))
config.substitutions.append(('%FileCheck',
    os.path.join(build_dir, 'bin', 'FileCheck')))

# Common flags
config.substitutions.append(('%sfpu-bh-flags',
    '-triple riscv32 -mattr=+xttsfpu,+xttsfpubh'))
config.substitutions.append(('%sfpu-wh-flags',
    '-triple riscv32 -mattr=+xttsfpu,+xttsfpuwh'))
