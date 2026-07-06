#!/usr/bin/env python3
"""
战棋地图3D可视化编辑器
功能：
1. 三维图层系统 - 每个格子支持多层不同类型地块
2. 三种交互模式：
   - 放置模式：点击/拖动放置地块（叠在已有地块顶部）
   - 面放置模式：点击已有地块的6个面，在该面方向放置新地块
   - 移动模式：左键拖动平移视角
3. 中键拖动旋转、滚轮缩放、Q/E旋转
4. 保存到 battle_terrain_XXX.json
"""

import json
import os
import sys
import math

try:
    import pygame
    from pygame.locals import *
    from OpenGL.GL import *
    from OpenGL.GLU import *
except ImportError:
    print("错误：缺少依赖库，请安装：")
    print("pip install pygame PyOpenGL PyOpenGL_accelerate")
    sys.exit(1)

# 交互模式
MODE_PLACE = 0       # 放置模式：点击放地块到顶部
MODE_FACE_PLACE = 1  # 面放置模式：点击面放置
MODE_EDIT = 2        # 编辑模式：修改已有地块类型
MODE_MOVE = 3        # 移动模式：左键拖动平移视角

MODE_NAMES = {MODE_PLACE: "放置", MODE_FACE_PLACE: "面放置", MODE_EDIT: "编辑", MODE_MOVE: "移动"}
MODE_COLORS = {
    MODE_PLACE: (50, 120, 200, 255),
    MODE_FACE_PLACE: (180, 100, 200, 255),
    MODE_EDIT: (200, 160, 40, 255),
    MODE_MOVE: (100, 160, 80, 255),
}

# 中文字体路径（Windows系统字体）
def _find_chinese_font():
    """查找支持中文的系统字体"""
    candidates = [
        "C:/Windows/Fonts/msyh.ttc",    # 微软雅黑
        "C:/Windows/Fonts/simhei.ttf",   # 黑体
        "C:/Windows/Fonts/simsun.ttc",   # 宋体
        "C:/Windows/Fonts/msyhbd.ttc",   # 雅黑粗体
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None

CHINESE_FONT_PATH = _find_chinese_font()


# =============================================================================
# 地形类型配置
# =============================================================================
class TerrainTypeConfig:
    """地形类型配置"""
    def __init__(self, config_dict):
        self.terrain_type_id = config_dict.get("terrain_type_id", "")
        self.display_name = config_dict.get("display_name", "未命名")
        self.material_type = config_dict.get("material_type", "STONE")
        self.mass = config_dict.get("mass", 100.0)
        self.friction_coefficient = config_dict.get("friction_coefficient", 1.0)
        self.has_health = config_dict.get("has_health", True)
        self.custom_max_health = config_dict.get("custom_max_health", -1)
        self.is_attackable = config_dict.get("is_attackable", False)
        self.is_interactive = config_dict.get("is_interactive", False)
        self.transform_to_id = config_dict.get("transform_to_id", "")
        self.is_passable = config_dict.get("is_passable", True)
        self.base_height = config_dict.get("base_height", 0)
        self.material_coefficient = {"PLASTIC": 25, "WOOD": 20, "STONE": 30, "METAL": 30}.get(self.material_type, 20)
        self.max_health = self._calc_health()
        self.color = {
            "PLASTIC": (0.2, 0.85, 0.9, 1.0),
            "WOOD":    (0.72, 0.48, 0.15, 1.0),
            "STONE":   (0.58, 0.58, 0.62, 1.0),
            "METAL":   (0.7, 0.7, 0.78, 1.0),
        }.get(self.material_type, (0.5, 0.5, 0.5, 1.0))

    def _calc_health(self):
        if not self.has_health:
            return 0
        if self.custom_max_health >= 0:
            return self.custom_max_health
        return int(self.mass * self.material_coefficient)


# =============================================================================
# 地图数据 - 三维图层系统
# =============================================================================
class TerrainMap:
    """地形地图数据 - 支持(col, row)上的多层图层"""
    def __init__(self, battle_config_path, terrain_types_dir):
        self.battle_config_path = battle_config_path
        self.terrain_types_dir = terrain_types_dir
        self.terrain_types = {}
        self.terrain_type_names = []
        self.grid_cols = 10
        self.grid_rows = 10
        self.excluded_tiles = set()
        self.default_type = "stone_floor"
        # 核心数据: {(col, row): [type_id_layer0, type_id_layer1, ...]}
        self.tiles = {}

        self._load_terrain_types()
        self._load_battle_config()

    def _load_terrain_types(self):
        if not os.path.exists(self.terrain_types_dir):
            print(f"[WARN] 地形类型目录不存在: {self.terrain_types_dir}")
            return
        for filename in sorted(os.listdir(self.terrain_types_dir)):
            if filename.endswith(".json"):
                filepath = os.path.join(self.terrain_types_dir, filename)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                    tt = TerrainTypeConfig(config)
                    if tt.terrain_type_id:
                        self.terrain_types[tt.terrain_type_id] = tt
                        self.terrain_type_names.append(tt.terrain_type_id)
                        print(f"  加载地形类型: {tt.terrain_type_id} - {tt.display_name}")
                except Exception as e:
                    print(f"  [ERROR] 加载 {filename}: {e}")
        self.terrain_type_names.append("__DELETE__")
        print(f"  共加载 {len(self.terrain_types)} 个地形类型")

    def _load_battle_config(self):
        # 从 battle_XXX.json 读取网格尺寸
        if os.path.exists(self.battle_config_path):
            try:
                with open(self.battle_config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                self.grid_cols = config.get("grid_cols", 10)
                self.grid_rows = config.get("grid_rows", 10)
                # 读取初始地块类型（战斗配置中的可选项）
                self.default_type = config.get("initial_terrain_type", self.default_type)
            except Exception as e:
                print(f"[ERROR] 加载战斗配置: {e}")
        else:
            print(f"[WARN] 战斗配置不存在: {self.battle_config_path}")

        # 从 battle_terrain_XXX.json 读取地形数据
        config_dir = os.path.dirname(self.battle_config_path)
        config_name = os.path.splitext(os.path.basename(self.battle_config_path))[0]
        terrain_filename = config_name.replace("battle_", "battle_terrain_") + ".json"
        terrain_path = os.path.join(config_dir, terrain_filename)

        if not os.path.exists(terrain_path):
            print(f"[WARN] 地形配置不存在: {terrain_path}")
            return

        try:
            with open(terrain_path, 'r', encoding='utf-8') as f:
                terrain_data = json.load(f)
            terrain_config = terrain_data.get("terrain_config", {})
            for tile in terrain_config.get("excluded_tiles", []):
                c, r = tile.get("col", -1), tile.get("row", -1)
                if c >= 0 and r >= 0:
                    self.excluded_tiles.add((c, r))
            self.default_type = terrain_config.get("default_type", "stone_floor")
            for tile in terrain_config.get("tiles", []):
                col, row = tile.get("col", 0), tile.get("row", 0)
                # 新格式: layers 列表
                if "layers" in tile:
                    self.tiles[(col, row)] = list(tile["layers"])
                # 旧格式: type_id + height -> 转换
                else:
                    type_id = tile.get("type_id", tile.get("type", self.default_type))
                    height = tile.get("height", 0)
                    self.tiles[(col, row)] = [type_id] * (height + 1)
            print(f"  地图: {self.grid_cols}x{self.grid_rows}, {len(self.tiles)}个地块列, {len(self.excluded_tiles)}个排除")
        except Exception as e:
            print(f"[ERROR] 加载地形配置: {e}")

    def get_layers(self, col, row):
        """获取(col, row)的图层列表，排除格子返回None"""
        if (col, row) in self.excluded_tiles:
            return None
        return self.tiles.get((col, row), [])

    def get_column_height(self, col, row):
        """获取(col, row)的总高度（层数，不含None占位）"""
        layers = self.get_layers(col, row)
        if layers is None:
            return -1
        return sum(1 for t in layers if t is not None)

    def place_on_top(self, col, row, type_id):
        """在(col, row)顶部放置地块"""
        if (col, row) in self.excluded_tiles:
            self.excluded_tiles.discard((col, row))
        if (col, row) not in self.tiles:
            self.tiles[(col, row)] = []
        self.tiles[(col, row)].append(type_id)

    def place_at_face(self, col, row, layer, face, type_id):
        """根据面方向放置地块
        face: "top","bottom","left","right","front","back"
        返回 (new_col, new_row, new_layer) 或 None
        """
        if face == "top":
            nc, nr, nl = col, row, layer + 1
        elif face == "bottom":
            if layer == 0:
                return None  # 不能在地面下方放置
            nc, nr, nl = col, row, layer - 1
        elif face == "left":
            nc, nr, nl = col - 1, row, layer
        elif face == "right":
            nc, nr, nl = col + 1, row, layer
        elif face == "front":
            nc, nr, nl = col, row + 1, layer
        elif face == "back":
            nc, nr, nl = col, row - 1, layer
        else:
            return None

        # 边界检查
        if nc < 0 or nc >= self.grid_cols or nr < 0 or nr >= self.grid_rows:
            return None

        if type_id == "__DELETE__":
            # 删除指定层的地块
            self.delete_layer(nc, nr, nl)
            return (nc, nr, nl)

        # 确保列存在
        if (nc, nr) not in self.tiles:
            self.tiles[(nc, nr)] = []
        layers = self.tiles[(nc, nr)]

        # 面放置：只放一个方块，不补齐整列
        # 用 None 占位到目标层（渲染时跳过 None 层）
        while len(layers) <= nl:
            layers.append(None)

        # 放置
        layers[nl] = type_id

        self.excluded_tiles.discard((nc, nr))
        return (nc, nr, nl)

    def delete_layer(self, col, row, layer):
        """删除指定层"""
        if (col, row) in self.tiles:
            layers = self.tiles[(col, row)]
            if layer < len(layers):
                layers.pop(layer)
                if not layers:
                    del self.tiles[(col, row)]

    def set_layer_type(self, col, row, layer, type_id):
        """修改指定层的地块类型"""
        if type_id == "__DELETE__":
            self.delete_layer(col, row, layer)
            return
        if (col, row) not in self.tiles:
            self.tiles[(col, row)] = []
        layers = self.tiles[(col, row)]
        # 补齐到目标层
        while len(layers) <= layer:
            layers.append(self.default_type)
        layers[layer] = type_id

    def save_to_json(self):
        """保存到 battle_terrain_XXX.json"""
        try:
            config_dir = os.path.dirname(self.battle_config_path)
            config_name = os.path.splitext(os.path.basename(self.battle_config_path))[0]
            terrain_filename = config_name.replace("battle_", "battle_terrain_") + ".json"
            terrain_path = os.path.join(config_dir, terrain_filename)

            excluded_list = sorted(
                [{"col": c, "row": r} for c, r in self.excluded_tiles],
                key=lambda x: (x["col"], x["row"])
            )

            tiles_list = []
            for (col, row), layers in sorted(self.tiles.items()):
                # 过滤掉None占位，只保存实际地块类型
                filtered_layers = [t for t in layers if t is not None]
                if filtered_layers:
                    tiles_list.append({
                        "col": col,
                        "row": row,
                        "layers": filtered_layers,
                        "height": len(filtered_layers)
                    })

            terrain_config = {
                "terrain_config": {
                    "default_type": self.default_type,
                    "excluded_tiles": excluded_list,
                    "tiles": tiles_list
                },
                "description": f"{config_name}对应的地形配置",
                "notes": [
                    f"对应 {os.path.basename(self.battle_config_path)} 的地形数据",
                    "layers数组: 索引=层高, 值=地形类型ID",
                    "地形类型从 terrain_types 目录加载",
                    "保存时更新此文件的 tiles 数组"
                ]
            }

            with open(terrain_path, 'w', encoding='utf-8') as f:
                json.dump(terrain_config, f, indent=2, ensure_ascii=False)

            total_cubes = sum(len(v) for v in self.tiles.values())
            print(f"[SAVE] {terrain_path} ({total_cubes} 方块, {len(tiles_list)} 列, {len(excluded_list)} 排除)")
            return True
        except Exception as e:
            print(f"[ERROR] 保存失败: {e}")
            return False


# =============================================================================
# 3D渲染器 - 支持面感知拾取
# =============================================================================
class TerrainRenderer:
    """地形3D渲染引擎"""

    COLOR_CHECKER_A = (0.22, 0.22, 0.25, 1.0)
    COLOR_CHECKER_B = (0.32, 0.32, 0.35, 1.0)
    COLOR_GRID = (0.5, 0.5, 0.5, 0.6)
    COLOR_HIGHLIGHT = (1.0, 1.0, 0.0, 0.8)
    COLOR_DEFAULT = (0.55, 0.55, 0.6, 1.0)

    # 面放置预览颜色（半透明绿）
    COLOR_PREVIEW = (0.2, 1.0, 0.3, 0.4)

    def __init__(self, terrain_map):
        self.map = terrain_map
        self.tile_size = 1.0

        # 相机参数
        max_dim = max(terrain_map.grid_cols, terrain_map.grid_rows)
        self.camera_distance = max_dim * 1.1
        self.camera_angle_x = 55.0
        self.camera_angle_y = 45.0
        self.camera_target = [0.0, 0.0, 0.0]  # 相机看向的目标点
        self.min_distance = 3.0
        self.max_distance = max_dim * 5.0

        # 鼠标
        self.last_mouse_pos = (0, 0)
        self.selected_col = -1
        self.selected_row = -1
        self.selected_layer = -1

        # 面放置预览
        self.preview_col = -1
        self.preview_row = -1
        self.preview_layer = -1
        self.preview_face = None

    def init_opengl(self):
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        far = self.max_distance * 2.0
        gluPerspective(45, 1200 / 800, 0.1, far)
        glMatrixMode(GL_MODELVIEW)

        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST)

        glEnable(GL_LIGHTING)
        glEnable(GL_LIGHT0)
        glLightfv(GL_LIGHT0, GL_POSITION, [0.0, 100.0, 0.0, 1.0])
        glLightfv(GL_LIGHT0, GL_AMBIENT,  [0.5, 0.5, 0.5, 1.0])
        glLightfv(GL_LIGHT0, GL_DIFFUSE,  [0.9, 0.9, 0.9, 1.0])
        glLightfv(GL_LIGHT0, GL_SPECULAR, [0.3, 0.3, 0.3, 1.0])

        glEnable(GL_COLOR_MATERIAL)
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE)

        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

        glClearColor(0.08, 0.08, 0.12, 1.0)
        print(f"  OpenGL初始化: far={far:.0f}, cam_dist={self.camera_distance:.1f}")

    def _get_camera_pos(self):
        rad_yaw = math.radians(self.camera_angle_y)
        rad_pitch = math.radians(self.camera_angle_x)
        cx = self.camera_target[0] + self.camera_distance * math.cos(rad_yaw) * math.cos(rad_pitch)
        cy = self.camera_target[1] + self.camera_distance * math.sin(rad_pitch)
        cz = self.camera_target[2] + self.camera_distance * math.sin(rad_yaw) * math.cos(rad_pitch)
        return cx, cy, cz

    def render(self):
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        far = self.max_distance * 2.0
        gluPerspective(45, 1200 / 800, 0.1, far)
        glMatrixMode(GL_MODELVIEW)

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        glLoadIdentity()

        cx, cy, cz = self._get_camera_pos()
        tx, ty, tz = self.camera_target
        gluLookAt(cx, cy, cz, tx, ty, tz, 0, 1, 0)

        self._render_checkerboard()
        self._render_grid_lines()
        self._render_all_tiles()

        # 选中高亮
        if 0 <= self.selected_col < self.map.grid_cols and 0 <= self.selected_row < self.map.grid_rows:
            self._render_highlight(self.selected_col, self.selected_row, self.selected_layer)

        # 面放置预览
        if self.preview_col >= 0:
            self._render_preview(self.preview_col, self.preview_row, self.preview_layer, self.preview_face)

    def _render_checkerboard(self):
        glDisable(GL_LIGHTING)
        hc = self.map.grid_cols / 2.0
        hr = self.map.grid_rows / 2.0
        hs = self.tile_size / 2.0
        y = -0.005

        glBegin(GL_QUADS)
        for col in range(self.map.grid_cols):
            for row in range(self.map.grid_rows):
                if (col, row) in self.map.excluded_tiles:
                    glColor4f(0.1, 0.05, 0.05, 1.0)
                elif (col + row) % 2 == 0:
                    glColor4f(*self.COLOR_CHECKER_A)
                else:
                    glColor4f(*self.COLOR_CHECKER_B)
                x = (col - hc) * self.tile_size
                z = (row - hr) * self.tile_size
                glVertex3f(x - hs, y, z - hs)
                glVertex3f(x + hs, y, z - hs)
                glVertex3f(x + hs, y, z + hs)
                glVertex3f(x - hs, y, z + hs)
        glEnd()
        glEnable(GL_LIGHTING)

    def _render_grid_lines(self):
        glDisable(GL_LIGHTING)
        glColor4f(*self.COLOR_GRID)
        glLineWidth(1.0)
        hc = self.map.grid_cols / 2.0
        hr = self.map.grid_rows / 2.0
        y = 0.005

        glBegin(GL_LINES)
        for i in range(self.map.grid_rows + 1):
            z = (i - hr) * self.tile_size
            glVertex3f(-hc * self.tile_size, y, z)
            glVertex3f(hc * self.tile_size, y, z)
        for i in range(self.map.grid_cols + 1):
            x = (i - hc) * self.tile_size
            glVertex3f(x, y, -hr * self.tile_size)
            glVertex3f(x, y, hr * self.tile_size)
        glEnd()
        glEnable(GL_LIGHTING)

    def _render_all_tiles(self):
        hc = self.map.grid_cols / 2.0
        hr = self.map.grid_rows / 2.0
        rendered_positions = set()
        for (col, row), layers in self.map.tiles.items():
            rendered_positions.add((col, row))
            if not layers:
                continue
            x = (col - hc) * self.tile_size
            z = (row - hr) * self.tile_size
            for layer_idx, type_id in enumerate(layers):
                if type_id is None:
                    continue  # 跳过占位空洞（面放置产生的空层）
                if type_id in self.map.terrain_types:
                    color = self.map.terrain_types[type_id].color
                else:
                    color = self.COLOR_DEFAULT
                y = layer_idx * self.tile_size
                glColor4f(*color)
                self._render_cube(x, y, z, self.tile_size)

        # 未配置地块：用默认类型渲染第一层（layer 0）
        if self.map.default_type and self.map.default_type in self.map.terrain_types:
            default_color = self.map.terrain_types[self.map.default_type].color
            for col in range(self.map.grid_cols):
                for row in range(self.map.grid_rows):
                    if (col, row) in rendered_positions or (col, row) in self.map.excluded_tiles:
                        continue
                    x = (col - hc) * self.tile_size
                    z = (row - hr) * self.tile_size
                    glColor4f(*default_color)
                    self._render_cube(x, 0, z, self.tile_size)

    def _render_cube(self, x, y, z, size):
        hs = size / 2.0
        glBegin(GL_QUADS)
        # 顶面 (+Y)
        glNormal3f(0, 1, 0)
        glVertex3f(x - hs, y + hs, z + hs)
        glVertex3f(x + hs, y + hs, z + hs)
        glVertex3f(x + hs, y + hs, z - hs)
        glVertex3f(x - hs, y + hs, z - hs)
        # 底面 (-Y)
        glNormal3f(0, -1, 0)
        glVertex3f(x - hs, y - hs, z - hs)
        glVertex3f(x + hs, y - hs, z - hs)
        glVertex3f(x + hs, y - hs, z + hs)
        glVertex3f(x - hs, y - hs, z + hs)
        # 前面 (+Z)
        glNormal3f(0, 0, 1)
        glVertex3f(x - hs, y - hs, z + hs)
        glVertex3f(x + hs, y - hs, z + hs)
        glVertex3f(x + hs, y + hs, z + hs)
        glVertex3f(x - hs, y + hs, z + hs)
        # 后面 (-Z)
        glNormal3f(0, 0, -1)
        glVertex3f(x + hs, y - hs, z - hs)
        glVertex3f(x - hs, y - hs, z - hs)
        glVertex3f(x - hs, y + hs, z - hs)
        glVertex3f(x + hs, y + hs, z - hs)
        # 右面 (+X)
        glNormal3f(1, 0, 0)
        glVertex3f(x + hs, y - hs, z + hs)
        glVertex3f(x + hs, y - hs, z - hs)
        glVertex3f(x + hs, y + hs, z - hs)
        glVertex3f(x + hs, y + hs, z + hs)
        # 左面 (-X)
        glNormal3f(-1, 0, 0)
        glVertex3f(x - hs, y - hs, z - hs)
        glVertex3f(x - hs, y - hs, z + hs)
        glVertex3f(x - hs, y + hs, z + hs)
        glVertex3f(x - hs, y + hs, z - hs)
        glEnd()

    def _render_highlight(self, col, row, layer):
        """渲染选中方块的高亮线框"""
        hc = self.map.grid_cols / 2.0
        hr = self.map.grid_rows / 2.0
        x = (col - hc) * self.tile_size
        z = (row - hr) * self.tile_size
        y = layer * self.tile_size if layer >= 0 else -0.5
        hs = self.tile_size / 2.0

        glDisable(GL_LIGHTING)
        glColor4f(*self.COLOR_HIGHLIGHT)
        glLineWidth(3.0)
        # 顶面线框
        yt = y + hs
        glBegin(GL_LINE_LOOP)
        glVertex3f(x - hs, yt + 0.02, z - hs)
        glVertex3f(x + hs, yt + 0.02, z - hs)
        glVertex3f(x + hs, yt + 0.02, z + hs)
        glVertex3f(x - hs, yt + 0.02, z + hs)
        glEnd()
        # 竖直边线
        glBegin(GL_LINES)
        for dx in [-hs, hs]:
            for dz in [-hs, hs]:
                glVertex3f(x + dx, y - hs, z + dz)
                glVertex3f(x + dx, yt + 0.02, z + dz)
        glEnd()
        glLineWidth(1.0)
        glEnable(GL_LIGHTING)

    def _render_preview(self, col, row, layer, face):
        """渲染面放置预览（半透明方块）"""
        hc = self.map.grid_cols / 2.0
        hr = self.map.grid_rows / 2.0
        x = (col - hc) * self.tile_size
        z = (row - hr) * self.tile_size
        y = layer * self.tile_size

        glDisable(GL_LIGHTING)
        glDepthMask(GL_FALSE)
        glColor4f(*self.COLOR_PREVIEW)
        self._render_cube(x, y, z, self.tile_size)
        glDepthMask(GL_TRUE)
        glEnable(GL_LIGHTING)

    def pick_tile_3d(self, mouse_x, mouse_y, screen_w, screen_h):
        """三维射线拾取，返回 (col, row, layer, face) 或 (col, row, -1, None)"""
        win_x = float(mouse_x)
        win_y = float(screen_h - mouse_y)

        try:
            glReadBuffer(GL_FRONT)
            depth_data = glReadPixels(int(win_x), int(win_y), 1, 1, GL_DEPTH_COMPONENT, GL_FLOAT)
            if depth_data is None or len(depth_data) == 0:
                return -1, -1, -1, None
            depth = float(depth_data[0][0])
            if depth >= 1.0:
                return -1, -1, -1, None

            modelview = glGetDoublev(GL_MODELVIEW_MATRIX)
            projection = glGetDoublev(GL_PROJECTION_MATRIX)
            viewport = glGetIntegerv(GL_VIEWPORT)
            world = gluUnProject(win_x, win_y, depth, modelview, projection, viewport)

            wx, wy, wz = world[0], world[1], world[2]

            # 转换格子坐标
            col = int(wx / self.tile_size + self.map.grid_cols / 2.0)
            row = int(wz / self.tile_size + self.map.grid_rows / 2.0)

            if col < 0 or col >= self.map.grid_cols or row < 0 or row >= self.map.grid_rows:
                return -1, -1, -1, None

            # 确定层高
            layer = int(wy / self.tile_size + 0.5)  # 四舍五入到最近的层
            if layer < 0:
                layer = 0

            # 确定面
            face = self._detect_face(wx, wy, wz, col, row, layer)

            return col, row, layer, face
        except Exception:
            return -1, -1, -1, None

    def _detect_face(self, wx, wy, wz, col, row, layer):
        """根据世界坐标检测点击了立方体的哪个面"""
        hc = self.map.grid_cols / 2.0
        hr = self.map.grid_rows / 2.0
        cx = (col - hc) * self.tile_size  # 立方体中心X
        cz = (row - hr) * self.tile_size  # 立方体中心Z
        cy = layer * self.tile_size        # 立方体中心Y
        hs = self.tile_size / 2.0

        # 计算到各面的距离
        dist_top = abs(wy - (cy + hs))
        dist_bottom = abs(wy - (cy - hs))
        dist_right = abs(wx - (cx + hs))
        dist_left = abs(wx - (cx - hs))
        dist_front = abs(wz - (cz + hs))
        dist_back = abs(wz - (cz - hs))

        min_dist = min(dist_top, dist_bottom, dist_right, dist_left, dist_front, dist_back)

        if min_dist == dist_top: return "top"
        if min_dist == dist_bottom: return "bottom"
        if min_dist == dist_right: return "right"
        if min_dist == dist_left: return "left"
        if min_dist == dist_front: return "front"
        return "back"

    def get_face_placement_target(self, col, row, layer, face):
        """根据点击的面计算新方块的放置位置，返回 (col, row, layer) 或 None"""
        if face == "top":
            return (col, row, layer + 1)
        elif face == "bottom":
            if layer <= 0:
                return (col, row, 0)
            return (col, row, layer - 1)
        elif face == "left":
            return (col - 1, row, layer)
        elif face == "right":
            return (col + 1, row, layer)
        elif face == "front":
            return (col, row + 1, layer)
        elif face == "back":
            return (col, row - 1, layer)
        return None

    def zoom(self, delta):
        self.camera_distance *= (1.0 - delta * 0.1)
        self.camera_distance = max(self.min_distance, min(self.max_distance, self.camera_distance))

    def pan_camera(self, dx, dy):
        """平移相机目标点"""
        rad_yaw = math.radians(self.camera_angle_y)
        # 相机右方向和上方向
        right_x = math.cos(rad_yaw + math.pi / 2)
        right_z = math.sin(rad_yaw + math.pi / 2)
        up_x = -math.cos(rad_yaw) * math.sin(math.radians(self.camera_angle_x))
        up_z = -math.sin(rad_yaw) * math.sin(math.radians(self.camera_angle_x))

        speed = self.camera_distance * 0.003
        self.camera_target[0] += (right_x * dx + up_x * dy) * speed
        self.camera_target[2] += (right_z * dx + up_z * dy) * speed
        self.camera_target[1] += dy * speed * 0.5


# =============================================================================
# UI界面
# =============================================================================
class TerrainEditorUI:
    """地形编辑器UI界面"""

    PANEL_HEIGHT = 120  # 加高面板以容纳模式按钮

    def __init__(self, screen_width, screen_height, terrain_map):
        self.screen_width = screen_width
        self.screen_height = screen_height
        self.map = terrain_map
        self.panel_y = screen_height - self.PANEL_HEIGHT

        self.selected_type_index = 0
        self.selected_type_id = terrain_map.terrain_type_names[0] if terrain_map.terrain_type_names else ""

        # 当前模式
        self.current_mode = MODE_PLACE

        # 地形按钮布局
        self.type_btn_width = 120
        self.type_btn_height = 28
        self.type_btn_margin = 6
        self.types_per_row = max(1, (screen_width - 200) // (self.type_btn_width + self.type_btn_margin))

        # 预计算地形按钮位置
        self._type_btn_rects = []
        self._build_type_btn_rects()

        # 模式按钮位置
        mode_y = self.panel_y + 5
        mode_w = 72
        mode_h = 28
        mode_margin = 5
        self.mode_btn_rects = {}
        for i, mode in enumerate([MODE_PLACE, MODE_FACE_PLACE, MODE_EDIT, MODE_MOVE]):
            bx = 10 + i * (mode_w + mode_margin)
            self.mode_btn_rects[mode] = pygame.Rect(bx, mode_y, mode_w, mode_h)

        # 保存按钮
        self.save_rect = pygame.Rect(screen_width - 100, mode_y, 90, mode_h)

        # 字体和纹理
        self.font = None
        self.font_small = None
        self.ui_texture_id = None

    def _build_type_btn_rects(self):
        self._type_btn_rects = []
        type_start_y = self.panel_y + 40
        for i, type_name in enumerate(self.map.terrain_type_names):
            row_idx = i // self.types_per_row
            col_idx = i % self.types_per_row
            bx = 10 + col_idx * (self.type_btn_width + self.type_btn_margin)
            by = type_start_y + row_idx * (self.type_btn_height + 4)
            self._type_btn_rects.append(pygame.Rect(bx, by, self.type_btn_width, self.type_btn_height))

    def _init_fonts(self):
        if self.font is None:
            pygame.font.init()
            if CHINESE_FONT_PATH:
                try:
                    self.font = pygame.font.Font(CHINESE_FONT_PATH, 18)
                    self.font_small = pygame.font.Font(CHINESE_FONT_PATH, 14)
                except Exception:
                    self.font = pygame.font.Font(None, 20)
                    self.font_small = pygame.font.Font(None, 16)
            else:
                self.font = pygame.font.Font(None, 20)
                self.font_small = pygame.font.Font(None, 16)

    def render(self):
        self._init_fonts()

        ui_surface = pygame.Surface((self.screen_width, self.screen_height), pygame.SRCALPHA)
        ui_surface.fill((0, 0, 0, 0))

        # 面板背景
        panel_rect = pygame.Rect(0, self.panel_y, self.screen_width, self.PANEL_HEIGHT)
        pygame.draw.rect(ui_surface, (30, 30, 35, 240), panel_rect)
        pygame.draw.line(ui_surface, (80, 80, 90, 255), (0, self.panel_y), (self.screen_width, self.panel_y), 2)

        # 模式按钮
        for mode, rect in self.mode_btn_rects.items():
            color = MODE_COLORS[mode]
            if self.current_mode == mode:
                pygame.draw.rect(ui_surface, (255, 255, 80, 255), rect.inflate(4, 4), 2)
            pygame.draw.rect(ui_surface, color, rect, border_radius=3)
            text = self.font.render(MODE_NAMES[mode], True, (255, 255, 255))
            ui_surface.blit(text, text.get_rect(center=rect.center))

        # 保存按钮
        pygame.draw.rect(ui_surface, (40, 140, 40, 255), self.save_rect, border_radius=3)
        save_text = self.font.render("保存", True, (255, 255, 255))
        ui_surface.blit(save_text, save_text.get_rect(center=self.save_rect.center))

        # 地形类型按钮
        for i, type_name in enumerate(self.map.terrain_type_names):
            if i >= len(self._type_btn_rects):
                break
            btn_rect = self._type_btn_rects[i]

            if type_name == "__DELETE__":
                btn_color = (160, 45, 45, 255)
                label = "删除"
            elif type_name in self.map.terrain_types:
                tt = self.map.terrain_types[type_name]
                c = tt.color
                btn_color = (int(c[0] * 200), int(c[1] * 200), int(c[2] * 200), 255)
                label = tt.display_name
            else:
                btn_color = (80, 80, 80, 255)
                label = type_name

            if i == self.selected_type_index:
                pygame.draw.rect(ui_surface, (255, 255, 80, 255), btn_rect.inflate(4, 4), 2)
            pygame.draw.rect(ui_surface, btn_color, btn_rect, border_radius=3)
            text = self.font_small.render(label, True, (255, 255, 255))
            ui_surface.blit(text, text.get_rect(center=btn_rect.center))

        # 提示信息
        mode_hint = MODE_NAMES[self.current_mode]
        hints = {
            MODE_PLACE: "左键放置到顶部 | 右键滑动批量放置",
            MODE_FACE_PLACE: "左键点击面放置 | 右键滑动批量面放置",
            MODE_EDIT: "左键修改已有地块类型 | 右键滑动批量修改",
            MODE_MOVE: "左键拖动平移视角",
        }
        hint = f"模式:{mode_hint} | {hints[self.current_mode]} | 中键旋转 | 滚轮缩放 | Q/E旋转 | S保存 | ESC退出"
        hint_surf = self.font_small.render(hint, True, (150, 150, 160))
        ui_surface.blit(hint_surf, (10, self.panel_y + self.PANEL_HEIGHT - 14))

        self._render_surface_as_texture(ui_surface)

    def _render_surface_as_texture(self, surface):
        tex_data = pygame.image.tostring(surface, "RGBA", True)
        width = surface.get_width()
        height = surface.get_height()

        if self.ui_texture_id is None:
            self.ui_texture_id = glGenTextures(1)

        glBindTexture(GL_TEXTURE_2D, self.ui_texture_id)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, tex_data)

        glEnable(GL_TEXTURE_2D)
        glBindTexture(GL_TEXTURE_2D, self.ui_texture_id)
        glDisable(GL_DEPTH_TEST)
        glDisable(GL_LIGHTING)

        glMatrixMode(GL_PROJECTION)
        glPushMatrix()
        glLoadIdentity()
        glOrtho(0, self.screen_width, 0, self.screen_height, -1, 1)
        glMatrixMode(GL_MODELVIEW)
        glPushMatrix()
        glLoadIdentity()

        glColor4f(1, 1, 1, 1)
        glBegin(GL_QUADS)
        glTexCoord2f(0, 0); glVertex2f(0, 0)
        glTexCoord2f(1, 0); glVertex2f(width, 0)
        glTexCoord2f(1, 1); glVertex2f(width, height)
        glTexCoord2f(0, 1); glVertex2f(0, height)
        glEnd()

        glMatrixMode(GL_PROJECTION)
        glPopMatrix()
        glMatrixMode(GL_MODELVIEW)
        glPopMatrix()

        glDisable(GL_TEXTURE_2D)
        glEnable(GL_DEPTH_TEST)
        glEnable(GL_LIGHTING)

    def handle_click(self, mouse_x, mouse_y):
        """处理UI区域点击，返回True表示已处理"""
        if mouse_y < self.panel_y:
            return False

        # 模式按钮
        for mode, rect in self.mode_btn_rects.items():
            if rect.collidepoint(mouse_x, mouse_y):
                self.current_mode = mode
                print(f"  [MODE] 切换到: {MODE_NAMES[mode]}")
                return True

        # 保存按钮
        if self.save_rect.collidepoint(mouse_x, mouse_y):
            self.map.save_to_json()
            return True

        # 地形类型按钮
        for i, type_name in enumerate(self.map.terrain_type_names):
            if i >= len(self._type_btn_rects):
                break
            btn_rect = self._type_btn_rects[i]
            if btn_rect.collidepoint(mouse_x, mouse_y):
                self.selected_type_index = i
                self.selected_type_id = type_name
                print(f"  [UI] 选中: {type_name}")
                return True

        return True  # 面板区域拦截


# =============================================================================
# 主编辑器
# =============================================================================
class TerrainEditor:
    """地形编辑器主类"""

    def __init__(self, battle_config_path, terrain_types_dir):
        print("[INIT] 初始化编辑器...")

        pygame.init()
        self.screen_width = 1200
        self.screen_height = 800
        self.screen = pygame.display.set_mode(
            (self.screen_width, self.screen_height), DOUBLEBUF | OPENGL
        )
        pygame.display.set_caption("战棋地图3D编辑器")

        print("[INIT] 加载数据...")
        self.map = TerrainMap(battle_config_path, terrain_types_dir)

        self.renderer = TerrainRenderer(self.map)
        self.renderer.init_opengl()

        self.ui = TerrainEditorUI(self.screen_width, self.screen_height, self.map)

        self.running = True
        self.is_dragging = False
        self.drag_button = None  # 1=左键, 2=中键, 3=右键

        print("[INIT] 编辑器初始化完成")

    def run(self):
        clock = pygame.time.Clock()
        while self.running:
            self._handle_events()
            self._render_frame()
            pygame.display.flip()
            clock.tick(60)
        pygame.quit()

    def _handle_events(self):
        for event in pygame.event.get():
            if event.type == QUIT:
                self.running = False
            elif event.type == KEYDOWN:
                self._on_key(event)
            elif event.type == MOUSEBUTTONDOWN:
                self._on_mouse_down(event)
            elif event.type == MOUSEBUTTONUP:
                self._on_mouse_up(event)
            elif event.type == MOUSEMOTION:
                self._on_mouse_move(event)
            elif event.type == MOUSEWHEEL:
                self.renderer.zoom(event.y)

    def _on_key(self, event):
        if event.key == K_ESCAPE:
            self.running = False
        elif event.key == K_s:
            self.map.save_to_json()
        elif event.key == K_q:
            self.renderer.camera_angle_y -= 15.0
        elif event.key == K_e:
            self.renderer.camera_angle_y += 15.0
        elif event.key == K_1:
            self.ui.current_mode = MODE_PLACE
        elif event.key == K_2:
            self.ui.current_mode = MODE_FACE_PLACE
        elif event.key == K_3:
            self.ui.current_mode = MODE_EDIT
        elif event.key == K_4:
            self.ui.current_mode = MODE_MOVE

    def _on_mouse_down(self, event):
        mx, my = event.pos

        # UI面板优先
        if my >= self.ui.panel_y:
            self.ui.handle_click(mx, my)
            return

        if event.button == 1:  # 左键
            mode = self.ui.current_mode
            if mode == MODE_MOVE:
                self.is_dragging = True
                self.drag_button = 1
                self.renderer.last_mouse_pos = (mx, my)
            elif mode == MODE_PLACE:
                col, row, layer, face = self.renderer.pick_tile_3d(mx, my, self.screen_width, self.screen_height)
                if col >= 0 and row >= 0:
                    if self.ui.selected_type_id == "__DELETE__":
                        # 删除指定层（点击到的方块）
                        self.map.delete_layer(col, row, layer)
                        self.renderer.selected_col = col
                        self.renderer.selected_row = row
                        self.renderer.selected_layer = max(0, layer - 1)
                    else:
                        self.map.place_on_top(col, row, self.ui.selected_type_id)
                        layers = self.map.get_layers(col, row)
                        self.renderer.selected_col = col
                        self.renderer.selected_row = row
                        self.renderer.selected_layer = len(layers) - 1 if layers else 0
            elif mode == MODE_FACE_PLACE:
                col, row, layer, face = self.renderer.pick_tile_3d(mx, my, self.screen_width, self.screen_height)
                if col >= 0 and row >= 0 and face is not None:
                    target = self.renderer.get_face_placement_target(col, row, layer, face)
                    if target:
                        nc, nr, nl = target
                        if 0 <= nc < self.map.grid_cols and 0 <= nr < self.map.grid_rows:
                            self.map.place_at_face(col, row, layer, face, self.ui.selected_type_id)
                            self.renderer.selected_col = nc
                            self.renderer.selected_row = nr
                            self.renderer.selected_layer = nl
                # 清除预览
                self.renderer.preview_col = -1

            elif mode == MODE_EDIT:
                col, row, layer, face = self.renderer.pick_tile_3d(mx, my, self.screen_width, self.screen_height)
                if col >= 0 and row >= 0:
                    # 修改点击到的层的类型
                    self.map.set_layer_type(col, row, layer, self.ui.selected_type_id)
                    self.renderer.selected_col = col
                    self.renderer.selected_row = row
                    self.renderer.selected_layer = layer

        elif event.button == 2:  # 中键：旋转
            self.is_dragging = True
            self.drag_button = 2
            self.renderer.last_mouse_pos = (mx, my)

        elif event.button == 3:  # 右键：批量放置
            self.is_dragging = True
            self.drag_button = 3
            self._do_place(mx, my)

    def _do_place(self, mx, my):
        """执行放置/编辑操作（用于右键拖动批量操作）"""
        mode = self.ui.current_mode
        col, row, layer, face = self.renderer.pick_tile_3d(mx, my, self.screen_width, self.screen_height)
        if col < 0 or row < 0:
            return

        if mode == MODE_PLACE:
            if self.ui.selected_type_id == "__DELETE__":
                self.map.delete_layer(col, row, layer)
            else:
                self.map.place_on_top(col, row, self.ui.selected_type_id)
        elif mode == MODE_FACE_PLACE:
            if face is not None:
                self.map.place_at_face(col, row, layer, face, self.ui.selected_type_id)
        elif mode == MODE_EDIT:
            self.map.set_layer_type(col, row, layer, self.ui.selected_type_id)

    def _on_mouse_up(self, event):
        if event.button in (1, 2, 3):
            self.is_dragging = False
            self.drag_button = None

    def _on_mouse_move(self, event):
        mx, my = event.pos

        if self.is_dragging:
            if self.drag_button == 2:  # 中键旋转
                dx = mx - self.renderer.last_mouse_pos[0]
                dy = my - self.renderer.last_mouse_pos[1]
                self.renderer.camera_angle_y += dx * 0.4
                self.renderer.camera_angle_x = max(5, min(89, self.renderer.camera_angle_x + dy * 0.4))
                self.renderer.last_mouse_pos = (mx, my)
                return

            elif self.drag_button == 1 and self.ui.current_mode == MODE_MOVE:
                # 左键+移动模式：平移
                dx = mx - self.renderer.last_mouse_pos[0]
                dy = my - self.renderer.last_mouse_pos[1]
                self.renderer.pan_camera(-dx, -dy)
                self.renderer.last_mouse_pos = (mx, my)
                return

            elif self.drag_button == 3:  # 右键批量放置
                self._do_place(mx, my)
                return

        # 悬停高亮和面放置预览
        col, row, layer, face = self.renderer.pick_tile_3d(mx, my, self.screen_width, self.screen_height)
        if col >= 0 and row >= 0:
            self.renderer.selected_col = col
            self.renderer.selected_row = row
            if self.ui.current_mode == MODE_FACE_PLACE and face is not None:
                target = self.renderer.get_face_placement_target(col, row, layer, face)
                if target:
                    nc, nr, nl = target
                    if 0 <= nc < self.map.grid_cols and 0 <= nr < self.map.grid_rows:
                        self.renderer.preview_col = nc
                        self.renderer.preview_row = nr
                        self.renderer.preview_layer = nl
                        self.renderer.preview_face = face
                    else:
                        self.renderer.preview_col = -1
                else:
                    self.renderer.preview_col = -1
            else:
                self.renderer.preview_col = -1

            # 设置高亮层
            layers = self.map.get_layers(col, row)
            if layers is not None and layer < len(layers):
                self.renderer.selected_layer = layer
            elif layers is not None:
                self.renderer.selected_layer = len(layers) - 1
            else:
                self.renderer.selected_layer = -1
        else:
            self.renderer.selected_col = -1
            self.renderer.preview_col = -1

    def _render_frame(self):
        try:
            self.renderer.render()
        except Exception as e:
            print(f"[ERROR] 渲染错误: {e}")
        try:
            self.ui.render()
        except Exception as e:
            print(f"[ERROR] UI渲染错误: {e}")
            import traceback
            traceback.print_exc()


# =============================================================================
# 主程序入口
# =============================================================================
def main():
    battle_config_path = "data/battles/battle_001.json"
    terrain_types_dir = "data/terrain_types"

    if len(sys.argv) > 1:
        battle_config_path = sys.argv[1]
    if len(sys.argv) > 2:
        terrain_types_dir = sys.argv[2]

    print("=" * 60)
    print("  战棋地图3D地形编辑器")
    print("=" * 60)
    print(f"  战斗配置: {battle_config_path}")
    print(f"  地形目录: {terrain_types_dir}")
    print("-" * 60)
    print("  操作说明:")
    print("    模式1-放置  : 左键点击放地块到顶部")
    print("    模式2-面放置: 左键点击面放置方块")
    print("    模式3-编辑  : 左键修改已有地块类型")
    print("    模式4-移动  : 左键拖动平移视角")
    print("    右键拖动    : 批量操作(当前模式)")
    print("    中键拖动    : 旋转视角")
    print("    滚轮        : 缩放")
    print("    Q/E         : 旋转视角")
    print("    1/2/3/4     : 切换模式")
    print("    S           : 保存")
    print("    ESC         : 退出")
    print("=" * 60)

    try:
        editor = TerrainEditor(battle_config_path, terrain_types_dir)
        editor.run()
    except Exception as e:
        print(f"[FATAL] 编辑器崩溃: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
