"""Re-export a recorded clip with the current zoom plan: python reexport.py <clip>"""
import json, sys
from pathlib import Path
import clips, rec
name = sys.argv[1]
meta = json.loads((rec.OUT / f'{name}.marks.json').read_text())
c = rec.Clip(name=name, marks=[tuple(m) for m in meta['marks']])
raw = Path(meta['raw'])
off = rec.click_offset_ms(raw, c)
spec = clips.CLIPS[name]
extra = spec[3](c, off) if len(spec) > 3 else {}
rec.export(name, raw, zooms=spec[2](c, off), **extra)
