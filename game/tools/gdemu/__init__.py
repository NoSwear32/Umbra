"""
gdemu - runs the engine-independent parts of a GDScript 4 project under CPython.

NOT a Godot replacement: it transpiles the GDScript files that do not touch the scene tree
(simulation, data layers, input logic, save logic, test suites) to Python and executes them
against a small runtime that mimics the GDScript semantics that matter (integer division,
float coercion of typed variables, Array/Dictionary/Packed* types, signals, JSON, files ...).
Its purpose is to execute code that could not be run in the real engine and to catch port
and test-suite mistakes; a green run is evidence, not proof, and never replaces a run in Godot.
"""
