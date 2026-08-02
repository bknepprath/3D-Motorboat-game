import os

import bpy


SOURCE = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_boat.glb")
TARGET = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_boat_refined.glb")


def material(name, color, roughness=0.55, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def assign(obj, mat):
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def add_ico(name, location, scale, mat, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=1.0,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return assign(obj, mat)


def add_box(name, location, dimensions, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return assign(obj, mat)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)

for obj in list(bpy.context.scene.objects):
    if obj.type in {"CAMERA", "LIGHT"}:
        bpy.data.objects.remove(obj, do_unlink=True)

helmet = material("DriverHelmet", (0.98, 0.68, 0.12), roughness=0.38)
visor = material("DriverVisor", (0.05, 0.34, 0.45), roughness=0.18, metallic=0.05)
vest = material("DriverVest", (0.92, 0.23, 0.10), roughness=0.48)
skin = material("DriverSkin", (0.76, 0.35, 0.20), roughness=0.7)
accent = material("DriverAccent", (0.20, 0.86, 0.76), roughness=0.28)
engine = material("EngineCowl", (0.035, 0.12, 0.16), roughness=0.3, metallic=0.2)
engine_band = material("EngineBand", (0.96, 0.35, 0.08), roughness=0.38)
exhaust = material("EngineExhaust", (1.0, 0.42, 0.06), roughness=0.2)

add_ico("DriverLifeVest", (0.0, 1.08, 0.82), (0.33, 0.46, 0.23), vest, subdivisions=2)
add_ico("DriverHead", (0.0, 1.62, 0.79), (0.24, 0.26, 0.24), skin, subdivisions=2)
add_ico("DriverHelmet", (0.0, 1.80, 0.79), (0.31, 0.20, 0.29), helmet, subdivisions=1)
add_box("DriverVisor", (0.0, 1.71, 0.55), (0.38, 0.08, 0.16), visor)
add_ico("DriverShoulderL", (-0.28, 1.20, 0.68), (0.11, 0.13, 0.13), accent, subdivisions=1)
add_ico("DriverShoulderR", (0.28, 1.20, 0.68), (0.11, 0.13, 0.13), accent, subdivisions=1)
add_box("EngineCowl", (0.0, 0.72, 1.42), (0.86, 0.34, 0.62), engine)
add_box("EngineBand", (0.0, 0.73, 1.08), (0.9, 0.08, 0.08), engine_band)
add_ico("EngineExhaustL", (-0.25, 0.61, 1.75), (0.11, 0.11, 0.16), exhaust, subdivisions=1)
add_ico("EngineExhaustR", (0.25, 0.61, 1.75), (0.11, 0.11, 0.16), exhaust, subdivisions=1)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=TARGET,
    export_format="GLB",
    export_cameras=False,
    export_lights=False,
    export_materials="EXPORT",
)
print(f"Wrote {TARGET}")
