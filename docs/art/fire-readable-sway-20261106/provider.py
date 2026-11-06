"""Extract unchanged response PNGs using the previous, preserved extraction tool."""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / 'fire-single-tongue-20261106'
spec = importlib.util.spec_from_file_location('prior_field_pipeline', PREVIOUS / 'field_pipeline.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.ROOT = ROOT
module.REPO = ROOT.parents[2]
module.JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-readable-sway-20261106')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['extract'])
    parser.add_argument('key')
    args = parser.parse_args()
    module.extract(args.key)
