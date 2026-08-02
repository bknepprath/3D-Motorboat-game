import os

import bpy


SOURCE = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_arch.glb")
TARGET = os.path.join(os.path.dirname(__file__), "assets", "wavebreak_arch_refined.glb")


def make_material(name, color, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.25
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 5.0
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
    if obj.name in {"Arch_Beacon_L", "Arch_Beacon_R"}:
        bpy.data.objects.remove(obj, do_unlink=True)

beacon_mat = make_material("GateBeacon", (1.0, 0.68, 0.08), emission=(1.0, 0.18, 0.03))
stripe_mat = make_material("GateStripe", (0.12, 0.88, 0.78), emission=(0.02, 0.32, 0.28))
moss_mat = make_material("ArchMoss", (0.10, 0.34, 0.28))

for x in (-4.45, 4.45):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.7, location=(x, 1.05, 0.28))
    moss = assign(bpy.context.object, moss_mat)
    moss.name = "ArchMossPatch"
    moss.scale = (1.15, 0.42, 0.78)

for x in (-3.2, 3.2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.34, location=(x, 5.35, 0.0))
    beacon = assign(bpy.context.object, beacon_mat)
    beacon.name = "GateBeacon"
    bpy.ops.mesh.primitive_torus_add(
        major_segments=12,
        minor_segments=6,
        location=(x, 5.35, 0.0),
        major_radius=0.48,
        minor_radius=0.05,
    )
    halo = assign(bpy.context.object, beacon_mat)
    halo.name = "GateBeaconHalo"

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 5.05, 0.0))
stripe = bpy.context.object
stripe.name = "GateUpperStripe"
stripe.dimensions = (5.8, 0.16, 0.12)
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
