import os

import bpy


TARGET = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_reef_refined.glb")


def make_material(name, color, roughness=0.85):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def assign(obj, mat):
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def add_rock(name, location, scale, mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0, location=location)
    obj = assign(bpy.context.object, mat)
    obj.name = name
    obj.scale = scale
    return obj


bpy.ops.wm.read_factory_settings(use_empty=True)

stone_dark = make_material("ReefStoneDark", (0.11, 0.22, 0.25))
stone_mid = make_material("ReefStoneMid", (0.18, 0.34, 0.37))
stone_light = make_material("ReefStoneLight", (0.30, 0.48, 0.48))
moss = make_material("ReefMoss", (0.10, 0.31, 0.25), roughness=0.95)

add_rock("ReefBaseL", (-3.1, 1.45, 0.2), (2.0, 1.65, 1.8), stone_dark)
add_rock("ReefPillarL", (-1.9, 2.65, -0.15), (1.45, 2.8, 1.35), stone_mid)
add_rock("ReefPillarC", (0.25, 3.35, 0.0), (1.8, 3.55, 1.55), stone_light)
add_rock("ReefPillarR", (2.1, 2.15, 0.25), (1.55, 2.35, 1.45), stone_mid)
add_rock("ReefBaseR", (3.45, 1.15, 0.1), (1.75, 1.35, 1.55), stone_dark)
add_rock("ReefCap", (0.25, 5.75, 0.0), (2.35, 1.15, 1.85), stone_light)
add_rock("ReefMossL", (-2.0, 1.3, 1.0), (0.9, 0.38, 0.55), moss)
add_rock("ReefMossR", (1.9, 1.1, 1.1), (0.85, 0.34, 0.5), moss)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=TARGET,
    export_format="GLB",
    export_cameras=False,
    export_lights=False,
    export_materials="EXPORT",
)
print(f"Wrote {TARGET}")
