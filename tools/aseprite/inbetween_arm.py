"""Make a half-extended punch frame from the fully extended one: lift the forearm+fist
(everything right of CUT_X within the arm rows) and slide it back toward the shoulder.
Usage: python tools/aseprite/inbetween_arm.py in.png out.png CUT_X Y0 Y1 SHIFT"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
cut_x, y0, y1, shift = map(int, sys.argv[3:7])
a = np.asarray(Image.open(src).convert("RGBA")).copy()
arm = a[y0:y1, cut_x:].copy()
a[y0:y1, cut_x:] = 0
region = a[y0:y1, cut_x - shift:a.shape[1] - shift]
op = arm[..., 3] > 0
region[op] = arm[op]
# trim now-empty columns on the right
cols = np.where(a[..., 3].any(0))[0]
Image.fromarray(a[:, :cols.max() + 1], "RGBA").save(dst)
print(dst, a[:, :cols.max() + 1].shape)
