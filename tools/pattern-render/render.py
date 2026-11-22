#!/usr/bin/env python3
"""Draw the JSON from pattern-render: front view and three-quarter view, painter's algorithm
with simple lighting. Usage: render.py in.json out.png [colour1 colour2 colour3]"""
import json, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

data = json.load(open(sys.argv[1]))
if not data["vertices"]:
    fig = plt.figure(figsize=(6, 2)); fig.text(0.5, 0.5, "nothing to draw (no round-by-round pieces)", ha="center")
    plt.savefig(sys.argv[2]); print("saved", sys.argv[2]); sys.exit(0)
V = np.array(data["vertices"], dtype=float)
T = np.array(data["triangles"], dtype=int)
palette = [tuple(c) for c in data.get("palette", [])] or [(0.56, 0.85, 0.8), (0.78, 0.72, 0.62), (0.93, 0.93, 0.93)]

def view(ax, yaw, pitch, title):
    P = V[:, :3]
    cy, sy, cp, sp = np.cos(yaw), np.sin(yaw), np.cos(pitch), np.sin(pitch)
    R = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]) @ np.eye(3)
    Rp = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    Q = P @ R.T @ Rp.T
    tri = Q[T]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    light = np.array([0.4, 0.6, 0.7]); light /= np.linalg.norm(light)
    lam = 0.35 + 0.65 * np.abs(n @ light)
    depth = tri[:, :, 2].mean(axis=1)
    order = np.argsort(depth)  # far (negative z) first
    cols = []
    for k in order:
        i = T[k, 0]
        ci = int(V[i, 3])
        base = np.array((1.0, 0.86, 0.30) if ci == -2 else (0.05, 0.05, 0.06) if ci < 0 else palette[min(ci, len(palette) - 1)])
        cols.append(np.clip(base * V[i, 4] * lam[k], 0, 1))
    pc = PolyCollection(tri[order][:, :, :2], facecolors=cols, edgecolors=cols, linewidths=0.2)
    ax.add_collection(pc)
    ax.set_xlim(Q[:, 0].min() - 0.5, Q[:, 0].max() + 0.5)
    ax.set_ylim(Q[:, 1].min() - 0.5, Q[:, 1].max() + 0.5)
    ax.set_aspect("equal"); ax.set_title(title); ax.set_facecolor("#f4f4f4")

fig, axes = plt.subplots(1, 3, figsize=(15, 5.5))
view(axes[0], 0, 0, "front")
view(axes[1], 0.6, 0.45, "three-quarter, from above")
view(axes[2], np.pi / 2, 0, "side")
plt.tight_layout(); plt.savefig(sys.argv[2], dpi=90)
print("saved", sys.argv[2])
