import sys, pf
from PIL import Image
p = pf.shot(pf.find_window(), sys.argv[1] if len(sys.argv) > 1 else 'm')
im = Image.open(p).convert('L').resize((200, 112))
print('mean', round(sum(im.get_flattened_data()) / (200 * 112), 1))
