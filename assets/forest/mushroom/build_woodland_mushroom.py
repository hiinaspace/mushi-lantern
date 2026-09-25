"""Build the project-authored pale woodland mushroom GLB and its albedo atlas.

Run with Blender 4.x/5.x:
  blender -b --python assets/forest/mushroom/build_woodland_mushroom.py

The mesh and generated texture are original project assets, dedicated to CC0.
"""

import bpy
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IMAGE_PATH = ROOT / "pale_woodland_albedo.png"
GLB_PATH = ROOT / "pale_woodland_mushroom.glb"
SIZE = 512


def noise(x, y):
    # Stable, inexpensive texture grain; no runtime procedural dependency.
    return (math.sin(x * 127.1 + y * 311.7) * 43758.5453) % 1.0


def paint_atlas():
    image = bpy.data.images.new("Pale woodland mushroom albedo", width=SIZE, height=SIZE, alpha=False)
    pixels = []
    for py in range(SIZE):
        v = py / (SIZE - 1)
        for px in range(SIZE):
            u = px / (SIZE - 1)
            grain = noise(px * 0.21, py * 0.23) - 0.5
            color = [0.72, 0.69, 0.61]
            # UV region for the cap's radial top projection.
            if 0.27 <= u <= 0.98 and 0.52 <= v <= 0.99:
                cx = (u - 0.625) / 0.35
                cy = (v - 0.755) / 0.235
                radius = math.sqrt(cx * cx + cy * cy)
                fleck = noise(px * 0.47, py * 0.39)
                rim = max(0.0, min(1.0, (radius - 0.69) * 2.2))
                color = [0.88 - 0.17 * rim, 0.86 - 0.18 * rim, 0.79 - 0.17 * rim]
                mottling = (fleck - 0.5) * 0.045 + grain * 0.018
                for channel in range(3):
                    color[channel] += mottling
                if fleck > 0.94 and radius > 0.35:
                    color = [color[0] - 0.14, color[1] - 0.13, color[2] - 0.11]
            # UV region for gills: U tracks azimuth and V tracks center-to-rim.
            elif 0.26 <= u <= 0.99 and 0.025 <= v <= 0.47:
                phase = (u - 0.26) / 0.73 * math.tau
                radial = (v - 0.025) / 0.445
                ribs = (0.5 + 0.5 * math.cos(phase * 80.0))
                shade = 0.86 - 0.18 * radial - 0.055 * ribs * radial + grain * 0.014
                color = [shade, shade * 0.985, shade * 0.94]
            # UV region for the stem side.
            elif 0.025 <= u <= 0.235 and 0.025 <= v <= 0.49:
                vein = 0.5 + 0.5 * math.cos((u - 0.025) / 0.21 * math.tau * 15.0)
                shade = 0.83 + 0.035 * vein + grain * 0.012
                color = [shade, shade * 0.985, shade * 0.93]
            pixels.extend((max(0.0, min(1.0, c)) for c in color))
            pixels.append(1.0)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(IMAGE_PATH)
    image.file_format = "PNG"
    image.save()
    return image


def add_vertex(verts, uvs, co, uv):
    verts.append(co)
    uvs.append(uv)
    return len(verts) - 1


def build_mesh(image):
    verts, faces, face_uvs = [], [], []

    # Gently curved tapered stem, with enough radial segments to stay smooth.
    stem_rings = 14
    stem_segments = 24
    for ring in range(stem_rings + 1):
        t = ring / stem_rings
        y = 0.035 + 0.94 * t
        radius = 0.13 * (1.0 - 0.32 * t) * (0.92 + 0.08 * math.sin(math.pi * t))
        lean = 0.035 * math.sin(t * math.pi * 0.9)
        for seg in range(stem_segments):
            angle = math.tau * seg / stem_segments
            x = lean + radius * math.cos(angle)
            z = radius * math.sin(angle)
            uv = (0.03 + 0.20 * seg / stem_segments, 0.035 + 0.43 * t)
            add_vertex(verts, [], (x, y, z), uv)
    stem_start = 0
    for ring in range(stem_rings):
        for seg in range(stem_segments):
            a = stem_start + ring * stem_segments + seg
            b = stem_start + ring * stem_segments + (seg + 1) % stem_segments
            c = b + stem_segments
            d = a + stem_segments
            faces.append((a, b, c, d))
            face_uvs.append([ (0.03 + .20 * seg / stem_segments, .035 + .43 * ring / stem_rings),
                              (0.03 + .20 * (seg + 1) / stem_segments, .035 + .43 * ring / stem_rings),
                              (0.03 + .20 * (seg + 1) / stem_segments, .035 + .43 * (ring + 1) / stem_rings),
                              (0.03 + .20 * seg / stem_segments, .035 + .43 * (ring + 1) / stem_rings) ])

    # Smooth bell-to-flat cap profile, slightly irregular at the edge.
    cap_rings = 22
    cap_segments = 64
    cap_start = len(verts)
    for ring in range(cap_rings + 1):
        r = ring / cap_rings
        for seg in range(cap_segments):
            angle = math.tau * seg / cap_segments
            waviness = 1.0 + 0.018 * math.sin(angle * 5.0 + 0.4) + 0.009 * math.sin(angle * 9.0)
            radius = 0.79 * r * waviness
            y = 1.06 + 0.76 * max(0.0, 1.0 - r * r) ** 0.92
            y += 0.018 * math.sin(angle * 4.0) * (r ** 5)
            x, z = radius * math.cos(angle), radius * math.sin(angle)
            uv = (0.625 + 0.35 * r * math.cos(angle), 0.755 + 0.235 * r * math.sin(angle))
            add_vertex(verts, [], (x, y, z), uv)
    for ring in range(cap_rings):
        for seg in range(cap_segments):
            a = cap_start + ring * cap_segments + seg
            b = cap_start + ring * cap_segments + (seg + 1) % cap_segments
            c = cap_start + (ring + 1) * cap_segments + (seg + 1) % cap_segments
            d = cap_start + (ring + 1) * cap_segments + seg
            faces.append((a, b, c, d))
            face_uvs.append([ (0.625 + .35 * (ring / cap_rings) * math.cos(math.tau * seg / cap_segments), .755 + .235 * (ring / cap_rings) * math.sin(math.tau * seg / cap_segments)),
                              (0.625 + .35 * (ring / cap_rings) * math.cos(math.tau * (seg + 1) / cap_segments), .755 + .235 * (ring / cap_rings) * math.sin(math.tau * (seg + 1) / cap_segments)),
                              (0.625 + .35 * ((ring + 1) / cap_rings) * math.cos(math.tau * (seg + 1) / cap_segments), .755 + .235 * ((ring + 1) / cap_rings) * math.sin(math.tau * (seg + 1) / cap_segments)),
                              (0.625 + .35 * ((ring + 1) / cap_rings) * math.cos(math.tau * seg / cap_segments), .755 + .235 * ((ring + 1) / cap_rings) * math.sin(math.tau * seg / cap_segments)) ])

    # A continuous shallow underside avoids spiky card edges at low viewing
    # angles. Fine radial gills live in this surface's cream-colored UV texture.
    underside_rings = 10
    underside_segments = 96
    underside_start = len(verts)
    for ring in range(underside_rings + 1):
        r = ring / underside_rings
        radius = 0.785 * r
        y = 1.045 + 0.018 * (1.0 - r * r)
        for seg in range(underside_segments):
            angle = math.tau * seg / underside_segments
            x = radius * math.cos(angle)
            z = radius * math.sin(angle)
            add_vertex(verts, [], (x, y, z), (0.265 + 0.715 * seg / underside_segments, 0.045 + 0.39 * r))
    for ring in range(underside_rings):
        for seg in range(underside_segments):
            a = underside_start + ring * underside_segments + seg
            b = underside_start + ring * underside_segments + (seg + 1) % underside_segments
            c = underside_start + (ring + 1) * underside_segments + (seg + 1) % underside_segments
            d = underside_start + (ring + 1) * underside_segments + seg
            faces.append((a, b, c, d))
            face_uvs.append([(0.265 + .715 * seg / underside_segments, .045 + .39 * ring / underside_rings),
                             (0.265 + .715 * (seg + 1) / underside_segments, .045 + .39 * ring / underside_rings),
                             (0.265 + .715 * (seg + 1) / underside_segments, .045 + .39 * (ring + 1) / underside_rings),
                             (0.265 + .715 * seg / underside_segments, .045 + .39 * (ring + 1) / underside_rings)])

    # Geometry above uses Godot/glTF's Y-up convention for readability. Blender
    # is Z-up, so rotate the vertices +90 degrees about X before Y-up export.
    # This keeps the exported GLB mesh itself upright, with no hidden node turn.
    verts = [(x, -z, y) for x, y, z in verts]
    mesh = bpy.data.meshes.new("Pale woodland fruit mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for local_index, loop_index in enumerate(poly.loop_indices):
            uv_layer.data[loop_index].uv = face_uvs[poly.index][local_index]
    obj = bpy.data.objects.new("Pale woodland mushroom", mesh)
    bpy.context.collection.objects.link(obj)

    material = bpy.data.materials.new("Pale cap, cream gills and stem")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Roughness"].default_value = 0.86
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    material.node_tree.links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    material.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    obj.data.materials.append(material)
    return obj


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    image = paint_atlas()
    obj = build_mesh(image)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB", export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_image_format="AUTO")
    triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
    print(f"Created {GLB_PATH}: {triangles} triangles, {len(obj.data.materials)} material, {SIZE}x{SIZE} albedo")


main()
