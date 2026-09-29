"""
The ten animation rows of a character sheet and the pose of every frame.

A pose is a plain dict (see Rig): body squash/lean/offset, foot and hand targets in the
character's own space, head offset, tail swing, face and effects. All characters share these
poses, so they all move identically and only their looks differ.
"""
import math

# name -> (frames, fps, loop)   - must match CharacterDef.default_animations() in the game
ANIMS = [
    ("idle", 4, 5.0, True),
    ("run", 6, 14.0, True),
    ("accel", 2, 8.0, True),
    ("jump_up", 2, 10.0, False),
    ("fall", 2, 8.0, True),
    ("fast_jump", 2, 12.0, True),
    ("wall", 2, 12.0, False),
    ("land", 2, 14.0, False),
    ("near_fall", 2, 10.0, True),
    ("gameover", 2, 6.0, True),
]

HIP = (64.0, 100.0)
SHOULDER = (66.0, 75.0)


def base():
    return {
        "sx": 1.0, "sy": 1.0, "rot": 0.0, "dx": 0.0, "dy": 0.0,
        "head": (0.0, 0.0, 0.0),
        "foot_f": (75.0, 120.0), "foot_b": (54.0, 120.0),
        "hand_f": (81.0, 91.0), "hand_b": (50.0, 91.0),
        "tail": 0.0, "eye": "open", "mouth": "smile", "fx": [], "ears": 0.0,
    }


def pose_for(anim, i):
    p = base()
    if anim == "idle":
        p["sy"] = (1.0, 1.012, 1.022, 1.012)[i]
        p["sx"] = (1.0, 0.996, 0.99, 0.996)[i]
        p["hand_f"] = (81.0, (91.0, 90.0, 89.0, 90.0)[i])
        p["hand_b"] = (50.0, (91.0, 90.0, 89.0, 90.0)[i])
        p["head"] = (0.0, (0.0, -0.4, -0.8, -0.4)[i], 0.0)
        p["tail"] = (0.0, 5.0, 0.0, -5.0)[i]
        p["ears"] = (0.0, 0.0, 1.0, 0.0)[i]
        p["eye"] = "blink" if i == 3 else "open"
    elif anim == "run":
        ph = 2.0 * math.pi * i / 6.0
        lift = lambda phase: 15.0 * max(0.0, math.cos(phase))
        p["foot_f"] = (66.0 + 19.0 * math.sin(ph), 120.0 - lift(ph))
        p["foot_b"] = (62.0 + 19.0 * math.sin(ph + math.pi), 120.0 - lift(ph + math.pi))
        p["hand_f"] = (74.0 + 15.0 * math.sin(ph + math.pi), 88.0 - 7.0 * max(0.0, math.cos(ph + math.pi)))
        p["hand_b"] = (58.0 + 15.0 * math.sin(ph), 88.0 - 7.0 * max(0.0, math.cos(ph)))
        p["dy"] = -2.6 * (0.5 - 0.5 * math.cos(2.0 * ph)) + 1.0
        p["rot"] = 9.0
        p["head"] = (2.0, 0.0, 0.0)
        p["tail"] = -9.0 + 6.0 * math.sin(ph)
        p["ears"] = -1.0
        p["eye"] = "determined"
        p["mouth"] = "open" if i % 3 == 0 else "smile"
    elif anim == "accel":
        p["rot"] = 15.0
        p["head"] = (3.0, 1.0, 0.0)
        p["foot_b"] = ((46.0, 116.0), (52.0, 120.0))[i]
        p["foot_f"] = ((78.0, 120.0), (82.0, 112.0))[i]
        p["hand_f"] = (86.0, 93.0)
        p["hand_b"] = (46.0, (84.0, 88.0)[i])
        p["dy"] = 1.0
        p["tail"] = -14.0
        p["ears"] = -1.5
        p["eye"] = "determined"
        p["mouth"] = "grit"
        p["fx"] = ["dust_back"]
    elif anim == "jump_up":
        p["sx"], p["sy"] = ((0.95, 1.07), (0.94, 1.09))[i]
        p["dy"] = (-2.0, -3.0)[i]
        p["foot_f"] = ((71.0, 110.0), (73.0, 108.0))[i]
        p["foot_b"] = ((56.0, 114.0), (52.0, 112.0))[i]
        p["hand_f"] = ((81.0, 66.0), (79.0, 62.0))[i]
        p["hand_b"] = ((51.0, 70.0), (52.0, 66.0))[i]
        p["head"] = (0.0, -1.0, 0.0)
        p["tail"] = (8.0, 14.0)[i]
        p["ears"] = 1.5
        p["eye"] = "happy"
        p["mouth"] = "open"
    elif anim == "fall":
        p["dy"] = -1.0
        p["foot_f"] = ((70.0, 116.0), (73.0, 113.0))[i]
        p["foot_b"] = ((56.0, 112.0), (54.0, 116.0))[i]
        p["hand_f"] = ((87.0, 66.0), (85.0, 71.0))[i]
        p["hand_b"] = ((43.0, 64.0), (45.0, 69.0))[i]
        p["tail"] = (16.0, 12.0)[i]
        p["ears"] = 2.5
        p["eye"] = "wide"
        p["mouth"] = "o"
    elif anim == "fast_jump":
        p["sx"], p["sy"] = 0.94, 1.07
        p["rot"] = (22.0, 25.0)[i]
        p["dy"] = -4.0
        p["foot_f"] = ((64.0, 113.0), (62.0, 115.0))[i]
        p["foot_b"] = ((48.0, 111.0), (50.0, 108.0))[i]
        p["hand_f"] = (52.0, (86.0, 84.0)[i])
        p["hand_b"] = (44.0, (91.0, 88.0)[i])
        p["head"] = (3.0, 0.0, 0.0)
        p["tail"] = -22.0
        p["ears"] = -3.0
        p["eye"] = "determined"
        p["mouth"] = "grit"
        p["fx"] = ["speed"]
    elif anim == "wall":
        p["rot"] = (-8.0, -13.0)[i]
        p["sx"] = (0.88, 0.96)[i]
        p["sy"] = (1.0, 1.03)[i]
        p["dx"] = 2.0
        p["foot_f"] = ((90.0, 106.0), (92.0, 98.0))[i]
        p["foot_b"] = ((60.0, 120.0), (58.0, 116.0))[i]
        p["hand_f"] = ((96.0, 78.0), (90.0, 74.0))[i]
        p["hand_b"] = ((92.0, 92.0), (84.0, 94.0))[i]
        p["head"] = (-1.0, 0.0, 0.0)
        p["tail"] = (12.0, 18.0)[i]
        p["ears"] = 2.0
        p["eye"] = "wide"
        p["mouth"] = "o"
        p["fx"] = ["impact"]
    elif anim == "land":
        p["sx"], p["sy"] = ((1.16, 0.78), (1.06, 0.92))[i]
        p["foot_f"] = ((84.0, 120.0), (79.0, 120.0))[i]
        p["foot_b"] = ((44.0, 120.0), (49.0, 120.0))[i]
        p["hand_f"] = ((88.0, 99.0), (82.0, 94.0))[i]
        p["hand_b"] = ((40.0, 99.0), (46.0, 94.0))[i]
        p["head"] = (1.0, 2.0, 0.0)
        p["tail"] = (-6.0, -2.0)[i]
        p["ears"] = -2.0
        p["eye"] = "blink" if i == 0 else "open"
        p["mouth"] = "grit" if i == 0 else "smile"
        p["fx"] = ["dust_both"] if i == 0 else []
    elif anim == "near_fall":
        p["hand_f"] = ((82.0, 58.0), (74.0, 54.0))[i]
        p["hand_b"] = ((46.0, 60.0), (56.0, 58.0))[i]
        p["foot_f"] = ((78.0, 116.0), (66.0, 120.0))[i]
        p["foot_b"] = ((50.0, 120.0), (62.0, 116.0))[i]
        p["dy"] = (-1.0, 0.0)[i]
        p["head"] = (0.0, 0.0, 0.0)
        p["tail"] = (15.0, 10.0)[i]
        p["ears"] = 3.0
        p["eye"] = "wide"
        p["mouth"] = "o"
        p["fx"] = ["sweat"]
    elif anim == "gameover":
        p["rot"] = (14.0, 12.0)[i]
        p["sy"] = 0.96
        p["dy"] = (2.0, 1.0)[i]
        p["foot_f"] = (79.0, 120.0)
        p["foot_b"] = (50.0, 118.0)
        p["hand_f"] = ((75.0, 99.0), (73.0, 100.0))[i]
        p["hand_b"] = ((57.0, 100.0), (55.0, 101.0))[i]
        p["head"] = (2.0, 2.0, 0.0)
        p["tail"] = (-4.0, -8.0)[i]
        p["ears"] = -3.0
        p["eye"] = "x"
        p["mouth"] = "tongue"
        p["fx"] = ["stars"]
    return p
