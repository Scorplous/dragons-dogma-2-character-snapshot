"""Run the synthetic regression suite from any working directory."""
import os
from pathlib import Path
import runpy
import sys
root=Path(__file__).resolve().parents[1]
os.chdir(root)
tests=sorted((root/'tests').glob('test_*.py'))
for test in tests:
    sys.argv=[str(test),'src/AtlasSnapshot-DD2.lua']
    print('\n'+test.name)
    runpy.run_path(str(test),run_name='__main__')
print(f'\nPassed {len(tests)} test modules. Synthetic tests do not replace game validation.')
