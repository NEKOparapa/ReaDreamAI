// lib/base/default_configs.dart

// 全局应用默认配置
const Map<String, dynamic> appDefaultConfigs = {
  // --- 应用设置 ---
  'isDarkMode': false,
  'proxy_enabled': false, // 代理开关，默认关闭
  'proxy_port': '7890',  // 代理端口，通用默认值
  
  // --- 阅读器设置  ---
  'reader_theme_id': 'default',
  'reader_font_size': 18.0,
  'reader_line_height': 1.8,
  'reader_font_family': 'SystemDefault',

  // --- 生图设置 ---
  'image_gen_tokens': 9000, // 生图使用的最大Token数
  'image_gen_scenes_per_chapter': 3, // 每章生成的场景数
  'image_gen_images_per_scene': 2, // 每个场景生成的图片数
  'image_gen_max_workers': 1, // 最大并发数
  'image_gen_size': '1024*1024',  // 图片尺寸

  // --- 视频设置 ---
  'video_gen_duration': 5, // 视频时长，单位秒
  'video_gen_resolution': '720p', // 视频分辨率

  // --- 小说转短剧设置 ---
  'storyboard_gen_selected_book_id': null, // 生成页面的小说ID，无默认值
  'storyboard_gen_requirements': '', // 分镜要求
  'storyboard_gen_character_ids': [], // 选中的角色ID
  'storyboard_gen_use_ai_chars': true, // 是否使用AI生成角色
  'storyboard_gen_scenes_per_chapter': 5, // 每章场景数
  'storyboard_gen_use_ai_scenes': true,    // 是否由AI决定场景数
  'storyboard_gen_shots_per_scene': 8,      // 每场景分镜数
  'storyboard_gen_use_ai_shots': true,      // 是否由AI决定分镜数
  'storyboard_gen_prompt_language': 'en', // 提示词语言, 'en' 或 'zh'

  // --- 工作台相关配置 ---
  'workbench_last_active_book_id': null, // 工作台最后打开的小说ID

  // 工作台默认角色数据
  'workbench_active_characters': [
    {
      'id': 'default_character_1',
      'name': '主角模板',
      'characterName': '李华',
      'identity': '普通高中生',
      'appearance': '黑发，眼神清澈，身材中等',
      'clothing': '白色T恤，蓝色校服裤',
      'personality': '善良，有点内向，但在关键时刻很可靠',
      'status': '正常',
      'other': '这是一个用于初始化的角色示例。',
      'referenceImageUrl': null,
      'referenceImagePath': null,
      'isSystemPreset': true,
    }
  ],

  // 工作台默认脚本数据 
  'workbench_active_script': [
    {
      'chapterNumber': 1,
      'originalChapterTitle': '第一章', // 标题会在加载时被实际章节名覆盖
      'scenes': [
        {
          'sceneNumber': 1,
          'title': '场景1：清晨的街道',
          'time': '日',
          'location': '外景',
          'shots': [
            {
              'shotNumber': 1,
              'shotType': '全景',
              'cameraMove': '固定',
              'characters': '李华',
              'content': '清晨的阳光洒在安静的街道上，三三两两的学生背着书包走向学校。李华独自一人走在人行道上，耳机里放着音乐。',
              'sound': '（环境音）清脆的鸟鸣，远处车辆驶过的声音。',
              'duration': '5s',
              'firstFramePrompt': '',
              'firstFrameImagePaths': [],
              'videoPrompt': '',
              'videoPaths': []
            },
            {
              'shotNumber': 2,
              'shotType': '近景',
              'cameraMove': '跟拍',
              'characters': '李华',
              'content': '镜头跟随李华的步伐，他低着头，表情有些落寞，似乎在思考着什么心事。',
              'sound': '（内心独白）“如果那天我能勇敢一点，现在会是怎样呢？”',
              'duration': '4s',
              'firstFramePrompt': '',
              'firstFrameImagePaths': [],
              'videoPrompt': '',
              'videoPaths': []
            }
          ]
        }
      ]
    }
  ],



  // --- 游戏媒体设置 ---
  'game_bgm_autoplay': true, // 背景音乐自动播放
  'game_bgm_loop': false,     // 背景音乐自动循环

  // ---创建游戏世界 ---
  'gamestage_gen_world_req': '',      // 游戏世界要求
  'gamestage_gen_player_req': '', // 玩家角色要求
  'gamestage_gen_destiny_req': '',    // 命运AI要求
  'gamestage_gen_char_ids': [],         // 手动选择的AI角色ID
  'gamestage_gen_use_ai_chars': true,   // 是否使用AI生成角色
  'gamestage_gen_ai_char_count': 3,       // 自定义AI角色数量
  'gamestage_gen_use_ai_char_count': true,// 是否由AI决定角色数量
  'gamestage_gen_scene_count': 5,       // 自定义游戏场景数
  'gamestage_gen_use_ai_scenes': true,  // 是否由AI决定场景数
  'gamestage_gen_gen_char_imgs': false, // 是否生成角色立绘
  'gamestage_gen_gen_scene_imgs': false, // 是否生成场景图片
  'gamestage_gen_gen_scene_music': false, // 是否生成场景音乐


  //---游戏舞台配置 ---
  'game_stage_book_title': '艾瑞多编年史', 

  'game_stage_world_background': '在一个名为"艾瑞多"的奇幻世界，魔法与科技交织共存。古老的巨龙沉睡在浮空山脉之上，而地面的城市则充满了蒸汽驱动的机械和闪烁的霓虹灯。各个种族——精灵、矮人、人类和兽人——在脆弱的和平中维持着微妙的平衡。',

  'game_stage_story_direction': '故事将围绕"源石"的争夺展开。一个古老的预言暗示，当源石之心被触动时，沉睡的巨龙将会苏醒，为世界带来毁灭或新生。玩家的选择将决定世界的最终命运。',

  'game_stage_player_character': {
    'name': '莉娜',
    'identity': '一位年轻的精灵魔法师，也是一位机械工程师学徒',
    'appearance': '拥有银色的长发和翠绿色的眼眸，常穿着便于活动的皮甲和沾满油污的工装裤。',
    'status': '健康，但对未来感到迷茫。',
    'equipment': '一把由自己改造的魔法步枪、一套简易工具。',
    'backpack': '几块干粮、水袋、一本破旧的机械图纸。'
  },

  'game_stage_ai_characters': [
    {
      'id': 'pre_char_1', 
      'cardName': '神秘铁匠-索林',
      'name': '索林',
      'identity': '隐居在深山中的矮人铁匠大师',
      'appearance': '身材矮壮，有着火红色的胡子，手臂上布满伤疤和纹身。',
      'personality': '外冷内热，沉默寡言，但对技艺有着极致的追求。',
      'motivation': '寻找传说中的"星辰之铁"，以锻造出超越神器的武器。',
      'status': '健康',
      'other': '似乎知道关于"源石"的古老秘密。',
      'equipment': '一把巨大的锻造锤、防火皮围裙。',
      'backpack': '稀有矿石样本、一壶烈酒。',
      'imagePath': null,
      'imagePrompt': ''
    },
    {
      'id': 'pre_char_2', 
      'cardName': '黑鸦-凯',
      'name': '凯',
      'identity': '"黑鸦"佣兵团的团长',
      'appearance': '黑发黑瞳，脸上有一道贯穿左眼的伤疤，总是穿着一身黑色的风衣。',
      'personality': '精明、冷酷，为了利益不择手段。',
      'motivation': '为"黑鸦"寻找一个安身立命之地，摆脱被大国当做棋子的命运。',
      'status': '轻伤',
      'other': '他的佣兵团正在接受一个神秘雇主的委托，目标似乎也是"源石"。',
      'equipment': '两把附魔匕首、一件轻型锁子甲。',
      'backpack': '任务卷轴、金币袋、治疗药水。',
      'imagePath': null,
      'imagePrompt': ''
    }
  ],

  'game_stage_game_scenes': [
    {
      'id': 'pre_scene_1', 
      'name': '钢之心城',
      'description': '一座由蒸汽驱动的巨大都市，是矮人工程学与人类商业野心的结晶。城市分为上层富人区和下层工业区，阶级矛盾尖锐。',
      'subsidiaryScenes': '下层贫民窟、蒸汽市场、城主府。',
      'status': '表面繁荣，暗流涌动。',
      // [可选] 预留媒体字段
      'imagePath': null,
      'imagePrompt': '',
      'musicPath': null,
      'musicPrompt': ''
    },
    {
      'id': 'pre_scene_2', 
      'name': '迷雾森林',
      'description': '精灵们的古老家园，森林深处隐藏着被遗忘的遗迹和强大的自然之灵。外来者很容易在变幻莫测的浓雾中迷失方向。',
      'subsidiaryScenes': '精灵哨站、古树之心、废弃神庙。',
      'status': '被古老的魔法笼罩，充满了未知的危险与机遇。',
      'imagePath': null,
      'imagePrompt': '',
      'musicPath': null,
      'musicPrompt': ''
    }
  ],

  // --- 第一天事件\---
  'game_stage_first_day_events': [
    {
      'title': '遗物之谜', // [更新] 添加 title 字段，对应 Workbench 显示
      'scene_id': 'pre_scene_1', // [更新] 尽量使用 ID 对应，如果 ID 对应不上 Workbench 会尝试用名字匹配
      'dialogues': [
        {'name': '莉娜', 'message': '（看着手中的遗物）这东西...到底是什么？'},
        {'name': '老乞丐', 'message': '嘿，小姑娘，别把那东西露出来，会被“清洁工”盯上的。'}
      ]
    },
    {
      'title': '市场惊魂', // [更新] 添加 title 字段
      'scene_id': 'pre_scene_1', // 依然发生在钢之心城
      'dialogues': [
        {'name': '机械警卫', 'message': '检测到非法魔力波动，请出示证件。'},
        {'name': '莉娜', 'message': '糟糕，忘了屏蔽它的信号了。'}
      ]
    }
  ],
  

  // --- 翻译设置 --- 
  'translation_tokens': 2000, // 翻译使用的最大Token数
  'translation_source_lang': 'ja', // 源语言
  'translation_target_lang': 'zh-CN', // 目标语言

  // --- ComfyUI节点设置 ---
  'comfyui_workflow_type': 'wai_illustrious', // 默认工作流类型代号
  'comfyui_system_workflow_path': 'assets/comfyui/WAI_NSFW-illustrious-SDXL工作流.json', // 系统预设工作流路径
  'comfyui_custom_workflow_path': '', // 自定义工作流路径
  'comfyui_positive_prompt_node_id': '6', // 正面提示词节点ID
  'comfyui_positive_prompt_field': 'text', // 正面提示词字段
  'comfyui_negative_prompt_node_id': '7', // 负面提示词节点ID
  'comfyui_negative_prompt_field': 'text', // 负面提示词字段
  'comfyui_batch_size_node_id': '5',      // 批处理大小（生图数量）节点ID
  'comfyui_batch_size_field': 'batch_size', // 批处理大小字段
  'comfyui_latent_image_node_id': '5',    // 图像尺寸（高宽）节点ID
  'comfyui_latent_width_field': 'width',   // 宽度
  'comfyui_latent_height_field': 'height', // 高度

  // --- ComfyUI视频节点设置 ---
  'comfyui_video_workflow_type': 'video_wan2_2_14B_i2v', // 默认视频工作流类型
  'comfyui_video_workflow_path': 'assets/comfyui/video/video_wan2_2_14B_i2v.json', // 系统预设视频工作流路径
  'comfyui_video_custom_workflow_path': '', // 自定义视频工作流路径
  'comfyui_video_positive_prompt_node_id': '93', // 视频正面提示词节点ID
  'comfyui_video_positive_prompt_field': 'text', // 视频正面提示词字段
  'comfyui_video_size_node_id': '98', // 视频尺寸（宽和高）节点ID
  'comfyui_video_width_field': 'width', // 视频宽度字段
  'comfyui_video_height_field': 'height', // 视频高度字段
  'comfyui_video_count_node_id': '98', // 视频数量节点ID 
  'comfyui_video_count_field': 'batch_size', // 视频数量字段
  'comfyui_video_image_node_id': '97', // 参考图片节点ID 
  'comfyui_video_image_field': 'image', // 参考图片字段

  // --- 接口管理设置 ---
  'languageApis': [], // 语言接口列表
  'drawingApis': [], // 绘图接口列表
  'videoApis': [], // 视频接口列表
  'activeLanguageApiId': null, // 当前激活的语言接口ID
  'activeDrawingApiId': null, // 当前激活的绘图接口ID
  'activeVideoApiId': null, // 当前激活的视频接口ID
  
  // --- AI小说创作接口设置 ---
  'ai_novel_creation_outline_api_id': null, // 生成大纲的接口ID，null表示使用默认
  'ai_novel_creation_plan_api_id': null, // 规划章节的接口ID，null表示使用默认
  'ai_novel_creation_generate_api_id': null, // 生成内容的接口ID，null表示使用默认

  // --- AI小说创作 ---
  'ai_novel_creation_prompt': '少年遇见少女的开篇故事', // 创作提示词
  'ai_novel_creation_chapter_count': 3, // 章节数
  'ai_novel_creation_words_per_chapter': 4000, // 每章字数
  'ai_novel_creation_title': '艾瑞多之心', // 小说标题
  'ai_novel_creation_introduction': '在魔法与科技交织的艾瑞多世界，年轻的精灵魔法师莉娜意外发现了一个古代遗物，从而卷入了一场关乎世界命运的巨大阴谋。',
  // 背景设定预设内容
  'ai_novel_creation_background_setting': '在一个名为“艾瑞多”的奇幻世界，魔法与科技交织共存。古老的巨龙沉睡在浮空山脉之上，而地面的城市则充满了蒸汽驱动的机械和闪烁的霓虹灯。各个种族——精灵、矮人、人类和兽人——在脆弱的和平中维持着微妙的平衡。', 
  // 写作风格预设内容
  'ai_novel_creation_writing_style': '采用第三人称有限视角，文笔细腻，注重角色心理活动的描写和环境氛围的渲染。节奏快慢结合，在紧张的动作场面中穿插宁静的思考时刻，语言风格偏向史诗感与诗意。',
  // 主要角色预设内容
  'ai_novel_creation_main_characters': [
    {
      "name": "莉娜·风语者",
      "identity": "一位年轻的精灵魔法师，也是一位机械工程师学徒",
      "appearance": "拥有银色的长发和翠绿色的眼眸，常穿着便于活动的皮甲和沾满油污的工装裤，背上背着一把由自己改造的魔法步枪。",
      "personality": "好奇心强，勇敢无畏，但内心深处对古老的魔法传统与新兴的科技文明之间的冲突感到迷茫。"
    }
  ], 
  // 故事大纲预设内容
  'ai_novel_creation_storyline': [
    {
      "chapter_id": 1,
      "chapter_title": "序章：生锈的齿轮与古老的符文",
      "chapter_summary": "在蒸汽弥漫的城市“钢之心”的下层区，莉娜发现了一个无法用现有科技解释的古代遗物。这个发现让她原本平静的生活卷入了巨大的阴谋之中。",
      "time_span": "一个下午",
      "setting_update": "主角莉娜登场；引入关键物品[古代遗物]；故事地点[钢之心]下层区。"
    },
    {
      "chapter_id": 2,
      "chapter_title": "第一章：来自天空的警告",
      "chapter_summary": "为了解读遗物，莉娜决定前往传说中的浮空山脉寻找答案。在旅途中，她遭遇了机械刺客的追杀，并得到了一位神秘矮人铁匠的帮助。",
      "time_span": "三天",
      "setting_update": "新角色[神秘矮人铁匠]登场；新地点[浮空山脉]；引入敌对势力[机械刺客]。"
    }
  ],

// --- 写作预设 ---
  // 背景设定
  'writing_background_cards': [
    {
      'id': 'system_modern_campus',
      'name': '现代校园',
      'content': '故事发生在当代一所综合性大学。校园里有现代化的教学楼、图书馆、实验室和宿舍楼。学生们使用智能手机、笔记本电脑，在食堂、操场、社团活动室之间穿梭。有考试压力、恋爱烦恼、实习就业等现实问题，也有青春的活力与梦想。',
      'isSystemPreset': true,
    },
    {
      'id': 'system_magic_world',
      'name': '魔法世界',
      'content': '这是一个纯粹的魔法世界。魔法学院矗立在云端，学生们骑着飞天扫帚上课。魔杖、咒语、魔药是日常生活的一部分。有光明魔法与黑暗魔法的对抗，古老的预言和神秘的魔法生物。巫师、法师们研究着各种魔法体系，从元素魔法到时空魔法，从召唤术到变形术。',
      'isSystemPreset': true,
    },
    {
      'id': 'system_cyber_future',
      'name': '赛博科技',
      'content': '2077年的超级都市，霓虹灯照亮永不停歇的夜晚。人体改造司空见惯，神经接口直连网络。巨型企业控制一切，街头帮派在阴影中生存。虚拟现实与现实边界模糊，AI与人类共存。飞行汽车穿梭在摩天大楼间，地下城充斥着改造人和黑客。',
      'isSystemPreset': true,
    }
  ],
  'active_writing_background_card_id': null,

  // 写作风格
  'writing_style_cards': [
    {
      'id': 'system_blunt_style',
      'name': '简单直白',
      'content': '句式简单，语言直白，以动作和对白推动剧情发展，心理描写较少，节奏紧凑，对各类器官的描写毫不避讳。',
      'isSystemPreset': true,
    },
    {
      'id': 'system_extreme_sensory',
      'name': '夸张狂放',
      'content': '极度夸张的感官描写，直白粗暴描写之中又带有夸张修辞，将细微的触感、声响、气味都放大到极致，每个场景都充满强烈的视觉冲击和感官直接的刺激，对各类器官的描写毫不避讳。',
      'isSystemPreset': true,
    },
    {
      'id': 'system_japanese_light_novel',
      'name': '日式轻小说',
      'content': '日式轻小说风格，大量使用内心独白和吐槽，人物对话充满个性。擅长用夸张的反应和表情描写来增强戏剧效果，节奏明快，画面感强，对各类器官的描写毫不避讳。',
      'isSystemPreset': true,
    },
  ],
  'active_writing_style_card_id': 'system_blunt_style',

  // --- 绘图标签设置 ---
  // 绘画风格
  'drawing_style_tags': [
    {
      'id': 'system_realistic_style',
      'name': '现实写真',
      'content': 'realistic, photo-realistic, ultra-realistic, hyper-realistic, 8k',
      "exampleImage": 'assets/drawing_style_example/realistic_style.jpeg',
      'isSystemPreset': true,
    },
    {
      'id': 'system_figurine_style',
      'name': '玩偶手办',
      'content': 'figure, figurine, toy, vinyl figure',
      "exampleImage": 'assets/drawing_style_example/figurine_style.jpeg',
      'isSystemPreset': true,
    },
    {
      'id': 'system_anime_style',
      'name': '动漫风格',
      'content': 'anime style, anime screencap, anime screenshot,anime coloring,',
      "exampleImage": 'assets/drawing_style_example/anime_style.jpeg',
      'isSystemPreset': true,
    },
    {
      'id': 'system_ghibli_style',
      'name': '吉卜力',
      'content': 'Studio Ghibli style, Hayao Miyazaki style, Ghibli anime',
      "exampleImage": 'assets/drawing_style_example/ghibli_style.jpeg',
      'isSystemPreset': true,
    },
    {
      'id': 'user_watercolor_style',
      'name': '水彩风格',
      'content': 'watercolor painting, soft edges, translucent layers, artistic brushstrokes',
      "exampleImage": 'assets/drawing_style_example/watercolor_style.png',
      'isSystemPreset': true,
    },
    {
      'id': 'user_pixel_art_style',
      'name': '像素艺术',
      'content': 'pixel art, 16-bit, retro game style, limited color palette',
      "exampleImage": 'assets/drawing_style_example/pixel_art_style.png',
      'isSystemPreset': true,
    },
  ],

  'active_drawing_style_tag_id': 'system_anime_style', 

  // 负面标签
  'drawing_negative_tags': [
    {
      'id': 'system_negative',
      'name': '通用负面',
      'content': 'worst quality, bad quality, worst detail, bad anatomy, bad hands, extra digits, fewer, extra, missing, error, watermark, unfinished, displeasing, chromatic aberration, signature, artistic error, username, scan',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_negative_tag_id': 'system_negative', // 负面标签通常默认激活


  // 其他标签
  'drawing_other_tags': [
    {
      'id': 'system_other',
      'name': '预设-其他标签',
      'content': 'nsfw, uncensored',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_other_tag_id': null,

  // 角色设定
  'drawing_character_cards': [
    {
      'id': 'custom_character1',
      'name': '黑长直少女',
      'characterName': '女生',
      'identity': '1girl, solo, student',
      'appearance': 'long hair, straight hair, black hair, bangs, black eyes, fair skin, beautiful face',
      'clothing': 'school uniform, sailor uniform, blue sailor collar, red necktie, white shirt, blue pleated skirt, black stockings, school shoes',
      'personality': '文静, 内向',
      'status': '',
      'other': '',
      'referenceImageUrl': null,
      'referenceImagePath': 'assets/character_example/student_girl.png',
      'isSystemPreset': true,
    },
    {
      'id': 'custom_character2',
      'name': '可爱萝莉',
      'characterName': '萝莉, loli',
      'identity': '1girl, solo, loli',
      'appearance': 'blonde hair, golden hair, twintails, long twintails, big eyes, round eyes, blue eyes, sparkly eyes, blush, cute face, small stature, childlike',
      'clothing': 'frilly dress, white dress, pink ribbons, bow, knee-high socks, mary janes, hair ribbons',
      'personality': '活泼, 开朗, 天真',
      'status': '开心',
      'other': '',
      'referenceImageUrl': null,
      'referenceImagePath': 'assets/character_example/cute_loli.png',
      'isSystemPreset': true,
    },
    {
      'id': 'custom_character3',
      'name': '猫娘女仆',
      'characterName': '猫娘, 女仆',
      'identity': '1girl, solo, catgirl, maid',
      'appearance': 'medium hair, fluffy hair, silver hair, cat ears, cat tail, yellow eyes, slit pupils, cute face',
      'clothing': 'maid outfit, frilly apron, maid headdress, puffy sleeves, black dress, white apron, bell collar, paw gloves',
      'personality': ' mischievous, loyal',
      'status': '',
      'other': '',
      'referenceImageUrl': null,
      'referenceImagePath': 'assets/character_example/catgirl_mid.png',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_character_card_ids': [], // 角色默认不激活

  // --- 提示词设置 ---
  'prompt_cards': [
    {
      'id': 'system_default_prompt',
      'name': '预设-角色向',
  "content": """你的任务是分析小说文本，识别具有强烈视觉表现力的关键场景，提取场景中的核心视觉要素（人物、动作、环境、情绪），生成结构化的英文绘图提示词。提示词生成规则与格式：
一、 提示词结构
1.  主体: 场景中的核心角色或物体是谁/是什么。
2.  外貌与特征: 角色的核心外貌，如发型、发色、眼瞳颜色、体型、以及任何显著特征（如伤疤、纹身）等。
3.  服装与配饰: 角色的穿着、饰品、等。
4.  姿态与情绪: 角色的动作、姿势、表情、眼神等。
5.  构图与镜头: 画面构图，镜头视角（如特写、全身、鸟瞰），角色位置等。
6.  环境与背景: 场景发生的具体地点，背景中的元素等。
7.  氛围与光影: 整体氛围（如紧张、温暖），光线来源、颜色、阴影效果等。

二、 角色信息处理
- 一致性与继承：在为多个场景生成提示词时，如果都是同一个主体，其主体描述（如 外貌与特征、服装与配饰）应保持一致，且都需要重复和详细描写，以免不同的插图主体描述不一致。
- 优先级原则：如果在某个具体场景中，角色的服装、状态、情绪或配饰与【参考角色信息】不一致，优先采用【小说文本】中该场景的描述，或者进行补充。

三、 其他要求
- 视觉化语言: 使用具体、可被描绘的英文词汇，使用AI绘画相关的标签语言。
- 场景选择: 场景选择应尽可能分散在文本的不同阶段，并体现不同的情境或情绪，避免插图选取位置过于集中。
- 禁止任何艺术风格，艺术家名字，画质/渲染相关的词: 例如 `Impressionism`, `Anime`, `by Greg Rutkowski`, `masterpiece`, `best quality`, `4K`。
""",
      'isSystemPreset': true,
    },
    {
      'id': 'system_background_prompt',
      'name': '预设-平衡向',
      'content': '''你的任务是仔细分析小说文本，捕捉关键的角色、动作、环境和氛围，选择情感冲击力最强的时刻，提取最具画面感的场景，并为每个场景生成详细的英文绘图提示词。对于部分场景（约20%的场景），生成纯背景插图，专注于环境和氛围，而不包含任何角色或主体。
英文绘画提示词应该遵守以下要求:
- 从主体、外貌与特征、服装与配饰、姿态与情绪、构图与镜头、环境与背景、氛围与光影方面进行详细描绘。对于纯背景插图，省略主体、服装、姿态与情绪部分，专注于环境、背景、氛围与光影。
- 如果场景文本中角色的服装、状态或细节与角色参考信息不一致，优先使用场景文本中的描述。
- 尽量使用具体的视觉性语言，尽量使用AI绘画相关的标签语言。
- 不要包含任何艺术风格、画质或艺术家名字。''',
      'isSystemPreset': true,
    },
  ],
  'active_prompt_card_id': 'system_default_prompt', // 默认激活通用场景分析
};