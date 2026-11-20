"""Baut alle 3D-Modelle der Raketenwerft im Vinyl-Spielzeug-Stil und exportiert sie als .glb.

Aufruf (ohne Fenster):
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_models.py
Ausgabe: models/*.glb  (Blender: Z oben  ->  glTF/Godot: Y oben)
Materialnamen sind Absicht: Godot färbt "Paint" in der Stufenfarbe, "Accent" in der Akzentfarbe.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'models')
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


MATS = {}
def mat(name, color, rough=0.4, coat=0.5, metal=0.0, alpha=1.0, emit=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (*color, 1.0)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if 'Coat Weight' in b.inputs:
        b.inputs['Coat Weight'].default_value = coat
    if alpha < 1.0:
        b.inputs['Alpha'].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    if emit:
        b.inputs['Emission Color'].default_value = (*emit, 1.0)
        b.inputs['Emission Strength'].default_value = 1.0
    MATS[name] = m
    return m


def setmat(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)


def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True


def apply_mods(obj):
    for md in list(obj.modifiers):
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=md.name)


def finish(obj, bevel=0.0, bevel_seg=3, sub=0, solid=0.0):
    if solid:
        s = obj.modifiers.new('Solid', 'SOLIDIFY'); s.thickness = solid; s.offset = 0.0
    if bevel:
        b = obj.modifiers.new('Bevel', 'BEVEL'); b.width = bevel; b.segments = bevel_seg; b.limit_method = 'ANGLE'
    if sub:
        d = obj.modifiers.new('Sub', 'SUBSURF'); d.levels = sub; d.render_levels = sub
    apply_mods(obj)
    smooth(obj)
    return obj


def link(obj):
    if obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(obj)
    return obj


def sphere(r, loc=(0, 0, 0), scale=(1, 1, 1), m=None, seg=48):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=loc)
    o = bpy.context.active_object; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if m: setmat(o, m)
    smooth(o); return o


def cyl(r, h, loc=(0, 0, 0), m=None, seg=48, rot=(0, 0, 0), bevel=0.0, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=h, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r, radius2=r2, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    if m: setmat(o, m)
    if bevel: finish(o, bevel=bevel)
    else: smooth(o)
    return o


def box(size, loc=(0, 0, 0), m=None, bevel=0.0, rot=(0, 0, 0), sub=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if m: setmat(o, m)
    finish(o, bevel=bevel, sub=sub)
    return o


def torus(R, r, loc=(0, 0, 0), m=None, rot=(0, 0, 0), seg=64):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=16, location=loc, rotation=rot)
    o = bpy.context.active_object
    if m: setmat(o, m)
    smooth(o); return o


def lathe(profile, m=None, steps=64, name='Lathe'):
    """Drehkörper aus [(radius, höhe)] von unten nach oben"""
    me = bpy.data.meshes.new(name); o = bpy.data.objects.new(name, me); link(o)
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau, steps=steps, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    if m: setmat(o, m)
    smooth(o)
    bpy.context.view_layer.objects.active = o
    return o


def join(objs, name):
    objs = [o for o in objs if o]
    for o in bpy.context.selected_objects: o.select_set(False)
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active; o.name = name; o.data.name = name
    return o


def export(objs, fname):
    for o in bpy.context.selected_objects: o.select_set(False)
    for o in objs:
        o.select_set(True)
        for c in o.children_recursive: c.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, fname), export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_materials='EXPORT')
    print('EXPORT', fname)


def parent(child, par):
    child.parent = par
    child.matrix_parent_inverse = par.matrix_world.inverted()


# Farben im Vinyl-Look
SKIN = (1.0, 0.72, 0.52); HAIR = (0.33, 0.2, 0.12); WHITE = (0.95, 0.95, 0.97); ORANGE = (1.0, 0.42, 0.08)
DARK = (0.05, 0.05, 0.07); BOOT = (0.18, 0.2, 0.3); PINK = (1.0, 0.45, 0.45); BLUE = (0.2, 0.45, 0.95)

# =====================================================================
#  Paul, der Astronaut (ca. 1,8 hoch, Füße bei 0)
# =====================================================================
reset()
m_skin = mat('Skin', SKIN, 0.5, 0.25); m_hair = mat('Hair', HAIR, 0.55, 0.3); m_white = mat('Suit', WHITE, 0.42, 0.5)
m_acc = mat('Accent', ORANGE, 0.35, 0.7); m_dark = mat('Dark', DARK, 0.3, 0.6); m_boot = mat('Boot', BOOT, 0.4, 0.5)
m_pink = mat('Cheek', PINK, 0.6, 0.1); m_eyew = mat('EyeShine', (1, 1, 1), 0.2, 0.0); m_blue = mat('Patch', BLUE, 0.35, 0.7)
m_red = mat('Red', (0.95, 0.2, 0.25), 0.35, 0.7); m_green = mat('Green', (0.25, 0.85, 0.45), 0.35, 0.7)

root = bpy.data.objects.new('Paul', None); link(root)
parts = []
# Beine & Stiefel
for sx in (-1, 1):
    leg = cyl(0.14, 0.42, loc=(sx * 0.15, 0, 0.42), m=m_white, bevel=0.06); parts.append(leg)
    boot = box((0.26, 0.36, 0.2), loc=(sx * 0.15, 0.04, 0.1), m=m_boot, bevel=0.08, sub=1); parts.append(boot)
    sole = box((0.27, 0.37, 0.05), loc=(sx * 0.15, 0.04, 0.02), m=m_dark, bevel=0.02); parts.append(sole)
# Körper
body = box((0.66, 0.46, 0.66), loc=(0, 0, 0.92), m=m_white, bevel=0.2, sub=2); parts.append(body)
belt = torus(0.3, 0.05, loc=(0, 0, 0.68), m=m_acc); belt.scale = (1.08, 0.75, 1.0); parts.append(belt)
chest = box((0.3, 0.06, 0.2), loc=(0, -0.235, 0.98), m=m_acc, bevel=0.03, sub=1); parts.append(chest)
for k, mm in enumerate((m_red, m_green, m_blue)):
    parts.append(sphere(0.03, loc=(-0.08 + k * 0.08, -0.27, 0.98), m=mm, seg=16))
patch = box((0.12, 0.03, 0.08), loc=(0.2, -0.235, 1.12), m=m_blue, bevel=0.015); parts.append(patch)
pack = box((0.5, 0.24, 0.56), loc=(0, 0.3, 0.98), m=mat('Pack', (0.86, 0.88, 0.94), 0.4, 0.5), bevel=0.08, sub=1); parts.append(pack)
neck = torus(0.2, 0.06, loc=(0, 0, 1.27), m=m_acc); parts.append(neck)
bodyobj = join(parts, 'Body'); parent(bodyobj, root)
# Arme (Ursprung an der Schulter, damit Godot sie drehen kann)
for sx, nm in ((-1, 'ArmL'), (1, 'ArmR')):
    a = cyl(0.11, 0.42, loc=(0, 0, -0.2), m=m_white, bevel=0.05)
    glove = sphere(0.12, loc=(0, 0, -0.45), m=m_acc, seg=24)
    cuff = torus(0.11, 0.035, loc=(0, 0, -0.36), m=m_acc, seg=32)
    arm = join([a, glove, cuff], nm)
    arm.location = (sx * 0.4, 0, 1.14)
    bpy.ops.object.select_all(action='DESELECT')
    arm.rotation_euler = (0, sx * 0.25, 0)
    parent(arm, root)
# Kopf (Ursprung am Halsansatz)
hp = []
face = sphere(0.42, loc=(0, 0, 0.42), scale=(1.0, 0.96, 0.95), m=m_skin, seg=64); hp.append(face)
hair = sphere(0.435, loc=(0, 0.035, 0.46), m=m_hair, seg=64)
bm = bmesh.new(); bm.from_mesh(hair.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.0 and not (v.co.y > 0.15)], context='VERTS')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.2 and v.co.z < 0.18], context='VERTS')
bm.to_mesh(hair.data); bm.free(); finish(hair, solid=0.04); hp.append(hair)
for k in range(5):  # Pony
    a = -0.5 + k * 0.25
    hp.append(sphere(0.09, loc=(math.sin(a) * 0.34, -math.cos(a) * 0.3, 0.72 - abs(a) * 0.08), scale=(1.2, 0.8, 0.9), m=m_hair, seg=24))
for sx in (-1, 1):
    hp.append(sphere(0.062, loc=(sx * 0.14, -0.385, 0.46), scale=(0.85, 0.5, 1.15), m=m_dark, seg=24))
    hp.append(sphere(0.02, loc=(sx * 0.14 + 0.02, -0.415, 0.49), m=m_eyew, seg=12))
    brow = cyl(0.022, 0.15, loc=(sx * 0.14, -0.39, 0.6), m=m_dark, rot=(0, math.pi / 2, sx * -0.18), bevel=0.01); hp.append(brow)
    hp.append(sphere(0.07, loc=(sx * 0.42, 0, 0.42), scale=(0.5, 0.8, 1.0), m=m_skin, seg=24))
    hp.append(sphere(0.06, loc=(sx * 0.23, -0.34, 0.33), scale=(1.0, 0.4, 0.65), m=m_pink, seg=24))
nose = sphere(0.045, loc=(0, -0.41, 0.4), scale=(1, 0.8, 0.9), m=m_skin, seg=24); hp.append(nose)
# Lächeln: unterer Bogen eines Torus
sm = torus(0.11, 0.02, loc=(0, 0, 0), m=m_dark, rot=(math.pi / 2, 0, 0))
bm = bmesh.new(); bm.from_mesh(sm.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > -0.03], context='VERTS')   # nach dem Drehen ist Y in den Daten noch lokal
bm.to_mesh(sm.data); bm.free()
sm.location = (0, -0.4, 0.33); sm.scale = (1.0, 1.0, 0.7)
bpy.ops.object.select_all(action='DESELECT'); sm.select_set(True); bpy.context.view_layer.objects.active = sm
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
hp.append(sm)
# Helm: runde Glaskugel über dem Kopf (Spielzeug-Astronaut), unten ein dicker Kragenring
collar = torus(0.37, 0.075, loc=(0, 0, 0.03), m=m_white, seg=64); hp.append(collar)
stripe = torus(0.37, 0.03, loc=(0, -0.0, 0.085), m=m_acc, seg=64); stripe.scale = (1.02, 1.02, 1.0); hp.append(stripe)
head = join(hp, 'Head'); head.location = (0, 0, 1.3); parent(head, root)
m_glass = mat('HelmetGlass', (0.8, 0.92, 1.0), 0.04, 1.0, alpha=0.16)
bubble = sphere(0.57, loc=(0, -0.02, 0.45 - 0.42), m=m_glass, seg=64)   # Kopf-Ursprung = Gesichtsmitte (0.42)
bm = bmesh.new(); bm.from_mesh(bubble.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.03 - 0.45], context='VERTS')
bm.to_mesh(bubble.data); bm.free()
bubble.name = 'Bubble'
bubble.parent = head   # in Kopf-Koordinaten, wackelt mit dem Kopf mit
# Antenne sitzt jetzt am Rucksack
ant = cyl(0.015, 0.3, loc=(0.18, 0.36, 1.38), m=m_dark); parent(ant, bodyobj)
tip = sphere(0.045, loc=(0.18, 0.36, 1.55), m=m_red, seg=16); parent(tip, bodyobj)
export([root], 'paul.glb')

# =====================================================================
#  Raketen-Bauteile (gleiche Maße wie im Spiel: Radius 1,25)
# =====================================================================
RC = 1.25
def M_white(): return mat('White', WHITE, 0.32, 0.7)
def M_paint(): return mat('Paint', (0.9, 0.22, 0.27), 0.3, 0.8)
def M_dark(): return mat('Dark', (0.2, 0.22, 0.28), 0.4, 0.5)
def M_metal(): return mat('Metal', (0.72, 0.76, 0.84), 0.3, 0.6)
def M_accent(): return mat('Accent', ORANGE, 0.3, 0.7)
def M_glass(): return mat('Glass', (0.25, 0.72, 1.0), 0.05, 1.0)
def M_shield(): return mat('Shield', (0.42, 0.28, 0.18), 0.6, 0.2)

# Tank-Segment (Höhe 3,2, Unterkante bei 0)
reset()
t = cyl(RC, 3.16, loc=(0, 0, 1.6), m=M_white(), seg=64, bevel=0.08)
r1 = torus(RC + 0.01, 0.07, loc=(0, 0, 0.06), m=M_metal(), seg=64)
r2 = torus(RC + 0.01, 0.07, loc=(0, 0, 3.14), m=M_metal(), seg=64)
band = cyl(RC + 0.02, 0.42, loc=(0, 0, 0.55), m=M_paint(), seg=64, bevel=0.05)
pts = []
for k in range(12):  # Nieten-Knubbel an den Ringen
    a = k / 12 * math.tau
    pts.append(sphere(0.05, loc=(math.cos(a) * (RC + 0.06), math.sin(a) * (RC + 0.06), 3.0), m=M_metal(), seg=12))
export([join([t, r1, r2, band] + pts, 'Tank')], 'tank.glb')

# Kapsel (Höhe 2,9, Unterkante bei 0)
reset()
body = lathe([(0.0, 0.32), (1.2, 0.32), (1.24, 0.42), (1.18, 0.6), (0.62, 2.05), (0.5, 2.25), (0.48, 2.5), (0.0, 2.5)], M_white(), name='CapBody')
finish(body, bevel=0.03, bevel_seg=2)
shield = lathe([(0.0, 0.0), (1.05, 0.03), (1.27, 0.14), (1.28, 0.34), (0.0, 0.34)], M_shield(), name='Shield'); finish(shield, bevel=0.03)
dock = torus(0.46, 0.06, loc=(0, 0, 2.5), m=M_accent())
cap_top = lathe([(0.45, 2.5), (0.42, 2.75), (0.25, 2.88), (0.0, 2.9)], M_accent(), name='CapTop')
parts = [body, shield, dock, cap_top]
for k, a in enumerate((-0.4, 0.4)):  # große runde Bullaugen
    n = Vector((math.sin(a), -math.cos(a), 0.45)).normalized()
    pos = Vector((math.sin(a) * 0.93, -math.cos(a) * 0.93, 1.3))
    rim = torus(0.25, 0.06, loc=pos, m=M_accent())
    rim.rotation_mode = 'QUATERNION'; rim.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(n)
    glass = sphere(0.24, loc=pos, scale=(1, 1, 1), m=M_glass(), seg=32)
    glass.rotation_mode = 'QUATERNION'; glass.rotation_quaternion = rim.rotation_quaternion
    glass.scale = (1, 1, 0.35)
    for o in (rim, glass):
        bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    parts += [rim, glass]
for k in range(4):  # Steuerdüsen
    a = k / 4 * math.tau + math.pi / 4
    parts.append(box((0.22, 0.22, 0.16), loc=(math.cos(a) * 0.98, math.sin(a) * 0.98, 1.55), m=M_metal(), bevel=0.05, rot=(0, 0, a)))
parts.append(cyl(0.015, 0.9, loc=(0.3, 0, 3.0), m=M_dark(), seg=8))
parts.append(sphere(0.05, loc=(0.3, 0, 3.45), m=mat('Red', (0.95, 0.2, 0.25), 0.35, 0.7), seg=12))
export([join(parts, 'Capsule')], 'capsule.glb')

# Düse (Höhe 1, Austritt Radius 1 – im Spiel skaliert)
reset()
prof = []
for i in range(14):
    tt = i / 13
    r = 0.3 + 0.7 * (1 - (1 - tt) ** 2.2)
    prof.append((r, 1.0 - tt))
prof.reverse()
bell = lathe(prof, M_dark(), name='Bell'); finish(bell, solid=0.05)
lip = torus(1.0, 0.06, loc=(0, 0, 0.0), m=M_accent())
throat = torus(0.31, 0.06, loc=(0, 0, 1.0), m=M_metal())
export([join([bell, lip, throat], 'Bell')], 'bell.glb')

# Flosse (Wurzel an x=0, Unterkante bei 0, Dicke in y)
reset()
me = bpy.data.meshes.new('Fin'); fin = bpy.data.objects.new('Fin', me); link(fin)
bm = bmesh.new()
poly = [(0, 0), (1.6, -0.5), (1.65, 0.3), (0, 2.8)]
top = [bm.verts.new((x, -0.07, z)) for x, z in poly]
bot = [bm.verts.new((x, 0.07, z)) for x, z in poly]
bm.faces.new(top); bm.faces.new(list(reversed(bot)))
for i in range(4):
    j = (i + 1) % 4
    bm.faces.new((top[i], top[j], bot[j], bot[i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
setmat(fin, M_paint()); finish(fin, bevel=0.06, bevel_seg=3)
export([fin], 'fin.glb')

# Booster (Unterkante bei 0)
reset()
b_body = cyl(0.62, 7.6, loc=(0, 0, 0.9 + 3.8), m=M_white(), seg=48, bevel=0.05)
b_nose = lathe([(0.62, 8.5), (0.6, 8.9), (0.45, 9.5), (0.2, 10.0), (0.0, 10.15)], M_paint(), name='BNose')
bands = [cyl(0.64, 0.35, loc=(0, 0, z), m=M_paint(), seg=48, bevel=0.04) for z in (2.0, 7.9)]
bprof = [(0.48, 0.0), (0.42, 0.3), (0.3, 0.7), (0.22, 0.9)]
b_bell = lathe(bprof, M_dark(), name='BBell'); finish(b_bell, solid=0.04)
b_lip = torus(0.48, 0.04, loc=(0, 0, 0), m=M_accent())
export([join([b_body, b_nose, b_bell, b_lip] + bands, 'Booster')], 'booster.glb')

# Stufentrenner (Höhe 0,45) mit Bolzen
reset()
ring = cyl(RC * 0.99, 0.45, loc=(0, 0, 0.225), m=M_dark(), seg=64, bevel=0.06)
bolts = []
for k in range(16):
    a = k / 16 * math.tau
    bolts.append(sphere(0.06, loc=(math.cos(a) * RC * 0.99, math.sin(a) * RC * 0.99, 0.225), m=M_accent(), seg=12))
export([join([ring] + bolts, 'Decoupler')], 'decoupler.glb')

# Triebwerks-Halterung (Höhe 0,6, oben Radius RC)
reset()
mount = lathe([(0.32, 0.0), (0.7, 0.3), (RC * 0.96, 0.6), (0.0, 0.6)], M_dark(), name='Mount'); finish(mount, bevel=0.03)
export([mount], 'mount.glb')

# =====================================================================
#  Kulisse: Spielzeugbäume, Häuschen, Wattewolke
# =====================================================================
reset()
trunk = cyl(0.35, 2.4, loc=(0, 0, 1.2), m=mat('Trunk', (0.55, 0.33, 0.18), 0.6, 0.2), seg=16, bevel=0.1)
leaves = [sphere(1.7, loc=(0, 0, 3.6), m=mat('Leaf', (0.3, 0.75, 0.3), 0.45, 0.4), seg=24),
          sphere(1.2, loc=(0.9, 0.3, 4.6), m=mat('Leaf', (0.3, 0.75, 0.3)), seg=24),
          sphere(1.1, loc=(-0.8, -0.4, 4.7), m=mat('Leaf', (0.3, 0.75, 0.3)), seg=24)]
export([join([trunk] + leaves, 'Tree')], 'tree.glb')

reset()
pine = [cyl(0.25, 1.5, loc=(0, 0, 0.75), m=mat('Trunk', (0.5, 0.3, 0.16), 0.6, 0.2), seg=12)]
for k, (r, z) in enumerate(((1.6, 2.0), (1.25, 3.2), (0.85, 4.3))):
    c = cyl(r, 1.8, loc=(0, 0, z), m=mat('Pine', (0.15, 0.55, 0.32), 0.45, 0.4), seg=24, r2=0.05, bevel=0.15)
    pine.append(c)
export([join(pine, 'Pine')], 'pine.glb')

reset()
house = [box((5, 4, 3.2), loc=(0, 0, 1.6), m=mat('Wall', (1.0, 0.93, 0.8), 0.5, 0.3), bevel=0.25),
         box((5.6, 4.4, 0.5), loc=(0, 0, 3.5), m=mat('Roof', (0.95, 0.35, 0.3), 0.4, 0.5), bevel=0.2),
         box((0.9, 0.2, 1.6), loc=(0, -2.0, 0.8), m=mat('Door', (0.4, 0.55, 0.95), 0.4, 0.5), bevel=0.1),
         box((0.9, 0.2, 0.9), loc=(1.5, -2.0, 1.9), m=mat('Glass', (0.6, 0.85, 1.0), 0.1, 0.8), bevel=0.1),
         box((0.9, 0.2, 0.9), loc=(-1.5, -2.0, 1.9), m=mat('Glass', (0.6, 0.85, 1.0), 0.1, 0.8), bevel=0.1)]
export([join(house, 'House')], 'house.glb')

reset()
puffs = []
for (x, y, z, r) in ((0, 0, 0, 1.0), (1.1, 0.2, -0.1, 0.8), (-1.0, -0.1, -0.15, 0.75), (0.5, 0.3, 0.5, 0.7), (-0.4, -0.2, 0.45, 0.65), (1.8, 0, -0.3, 0.5), (-1.7, 0.1, -0.3, 0.5)):
    puffs.append(sphere(r, loc=(x, y, z), m=mat('Cloud', (1.0, 1.0, 1.0), 0.85, 0.0), seg=32))
cl = join(puffs, 'Cloud'); d = cl.modifiers.new('Sub', 'SUBSURF'); d.levels = 1; apply_mods(cl); smooth(cl)
export([cl], 'cloud.glb')
print('FERTIG')
