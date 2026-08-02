import math
import os

import bpy


SOURCE = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_buoy.glb")
TARGET = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_buoy_refined.glb")


def make_material(name, color, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.28
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    return mat


def assign(obj, mat):
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)

for obj in list(bpy.context.scene.objects):
    if obj.type in {"CAMERA", "LIGHT"}:
        bpy.data.objects.remove(obj, do_unlink=True)

beacon_mat = make_material("BeaconGlow", (1.0, 0.72, 0.12), emission=(1.0, 0.25, 0.04))
stripe_mat = make_material("BeaconStripe", (0.12, 0.88, 0.82))
foam_mat = make_material("BuoyFoam", (0.58, 0.94, 0.87), emission=(0.08, 0.22, 0.18))

bpy.ops.mesh.primitive_torus_add(
    major_segments=12,
    minor_segments=6,
    location=(0.0, 0.42, 0.0),
    major_radius=0.72,
    minor_radius=0.07,
    rotation=(math.radians(90.0), 0.0, 0.0),
)
foam_ring = assign(bpy.context.object, foam_mat)
foam_ring.name = "Buoy_FoamRing"

bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.24, location=(0.0, 2.78, 0.0))
beacon = assign(bpy.context.object, beacon_mat)
beacon.name = "Buoy_Beacon"

bpy.ops.mesh.primitive_torus_add(
    major_segments=12,
    minor_segments=6,
    location=(0.0, 2.78, 0.0),
    major_radius=0.34,
    minor_radius=0.045,
    rotation=(math.radians(90.0), 0.0, 0.0),
)
halo = assign(bpy.context.object, beacon_mat)
halo.name = "Buoy_BeaconHalo"

for x in (-0.38, 0.38):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, 2.08, 0.0))
    stripe = bpy.context.object
    stripe.name = "Buoy_MarkerStripe"
    stripe.dimensions = (0.12, 0.26, 0.1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(stripe, stripe_mat)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=TARGET,
    export_format="GLB",
    export_cameras=False,
    export_lights=False,
    export_materials="EXPORT",
)
print(f"Wrote {TARGET}")
