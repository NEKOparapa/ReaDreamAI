// lib/base/default_configs.dart

// 全局应用默认配置
const Map<String, dynamic> appDefaultConfigs = {
  // --- 应用设置 ---
  'isDarkMode': false,
  'proxy_enabled': false, // 代理开关，默认关闭
  'proxy_port': '7890',  // 代理端口，通用默认值
  
  // --- 生图设置 ---
  'image_gen_tokens': 7000, // 生图使用的最大Token数
  'image_gen_scenes_per_chapter': 3, // 每章生成的场景数
  'image_gen_images_per_scene': 2, // 每个场景生成的图片数
  'image_gen_max_workers': 1, // 最大并发数
  'image_gen_size': '1024*1024',  // 图片尺寸

  // --- 视频设置 ---
  'video_gen_duration': 5, // 视频时长，单位秒
  'video_gen_resolution': '720p', // 视频分辨率

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
  
  // --- 绘图标签设置 ---
  // 绘画风格
  'drawing_style_tags': [
    {
      'id': 'system_realistic_style',
      'name': '现实写真',
      'content': 'realistic, photo-realistic, ultra-realistic, hyper-realistic',
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
      'content': 'anime style, anime screencap',
      "exampleImage": 'assets/drawing_style_example/anime_style.jpeg',
      'isSystemPreset': true,
    },
    {
      'id': 'system_ghibli_style',
      'name': '吉普力',
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

  // 其他标签
  'drawing_other_tags': [
    {
      'id': 'system_other',
      'name': '预设-其他标签',
      'content': 'nsfw',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_other_tag_id': null,

  // 角色设定
  'drawing_character_cards': [
    {
      'id': 'custom_character1',
      'name': '黑长直少女',
      'characterName': '少女',
      'identity': '1girl, solo, student',
      'appearance': 'long hair, straight hair, black hair, bangs, black eyes, fair skin, beautiful face',
      'clothing': 'school uniform, sailor uniform, blue sailor collar, red necktie, white shirt, blue pleated skirt, black stockings, school shoes',
      'other': '',
      'referenceImageUrl': null,
      'referenceImagePath': 'assets/character_example/student_girl.png',
      'isSystemPreset': true,
    },
    {
      'id': 'custom_character2',
      'name': '可爱萝莉',
      'characterName': '萝莉',
      'identity': '1girl, solo, loli',
      'appearance': 'blonde hair, golden hair, twintails, long twintails, big eyes, round eyes, blue eyes, sparkly eyes, blush, cute face, small stature, childlike',
      'clothing': 'frilly dress, white dress, pink ribbons, bow, knee-high socks, mary janes, hair ribbons',
      'other': '',
      'referenceImageUrl': null,
      'referenceImagePath': 'assets/character_example/cute_loli.png',
      'isSystemPreset': true,
    },
    {
      'id': 'custom_character4',
      'name': '魅魔少女',
      'characterName': '魅魔',
      'identity': '1girl, solo, succubus, demon girl',
      'appearance': 'long hair, wavy hair, purple hair, demon horns, bat wings, heart-shaped pupils, seductive eyes, pointed tail, attractive figure',
      'clothing': 'revealing outfit, black leather, straps, choker, thigh-high boots, fingerless gloves',
      'other': '',
      'referenceImageUrl': null,
      'referenceImagePath': 'assets/character_example/demon_girl.png',
      'isSystemPreset': true,
    },
    {
      'id': 'custom_character5',
      'name': '猫娘女仆',
      'characterName': '猫娘',
      'identity': '1girl, solo, catgirl, nekomimi, maid',
      'appearance': 'medium hair, fluffy hair, silver hair, cat ears, cat tail, yellow eyes, slit pupils, cute face',
      'clothing': 'maid outfit, frilly apron, maid headdress, puffy sleeves, black dress, white apron, bell collar, paw gloves',
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
      'content': '''你是一个专业的小说插图生成助手，仔细分析小说文本，捕捉关键的角色、动作、环境和氛围，选择情感冲击力最强的时刻，提取最具画面感的场景，并为每个场景生成详细的英文绘图提示词。
英文绘画提示词应该遵守以下要求:
- 从主体、服装与配饰、姿态与情绪、构图与镜头、环境与背景、氛围与光影方面进行详细描绘。
- 如果场景文本中角色的服装、状态或细节与角色参考信息不一致，优先使用场景文本中的描述。
- 尽量使用具体的视觉性语言，尽量使用AI绘画相关的标签语言。
- 不要包含任何艺术风格、画质或艺术家名字。''',
      'isSystemPreset': true,
    },
    {
      'id': 'system_background_prompt',
      'name': '预设-平衡向',
      'content': '''你是一个专业的小说插图生成助手，仔细分析小说文本，捕捉关键的角色、动作、环境和氛围，选择情感冲击力最强的时刻，提取最具画面感的场景，并为每个场景生成详细的英文绘图提示词。对于部分场景（约30%的场景），生成纯背景插图，专注于环境和氛围，而不包含任何角色或主体。
英文绘画提示词应该遵守以下要求:
- 从主体、服装与配饰、姿态与情绪、构图与镜头、环境与背景、氛围与光影方面进行详细描绘。对于纯背景插图，省略主体、服装、姿态与情绪部分，专注于环境、背景、氛围与光影。
- 如果场景文本中角色的服装、状态或细节与角色参考信息不一致，优先使用场景文本中的描述。
- 尽量使用具体的视觉性语言，尽量使用AI绘画相关的标签语言。
- 不要包含任何艺术风格、画质或艺术家名字。''',
      'isSystemPreset': true,
    },
  ],
  'active_prompt_card_id': 'system_default_prompt', // 默认激活通用场景分析
};
