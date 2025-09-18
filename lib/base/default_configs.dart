// lib/base/default_configs.dart

// 全局应用默认配置
const Map<String, dynamic> appDefaultConfigs = {
  // --- 应用设置 ---
  'isDarkMode': false,
  'proxy_enabled': false, // 代理开关，默认关闭
  'proxy_port': '7890',  // 代理端口，通用默认值
  
  // --- 生图设置 ---
  'image_gen_tokens': 5000,
  'image_gen_scenes_per_chapter': 3,
  'image_gen_images_per_scene': 2,
  'image_gen_max_workers': 1,
  'image_gen_size': '1024*1024', 

  // --- 视频设置 ---
  'video_gen_duration': 5,
  'video_gen_resolution': '720p',

  // --- 翻译设置 --- 
  'translation_tokens': 4000,
  'translation_source_lang': 'English',
  'translation_target_lang': '中文',

  // --- ComfyUI节点设置 ---
  'comfyui_workflow_type': 'wai_illustrious', // 默认工作流类型代号
  'comfyui_system_workflow_path': 'assets/comfyui/WAI_NSFW-illustrious-SDXL工作流.json', // 系统预设工作流路径
  'comfyui_custom_workflow_path': '', // 自定义工作流路径
  'comfyui_positive_prompt_node_id': '6',
  'comfyui_positive_prompt_field': 'text',
  'comfyui_negative_prompt_node_id': '7',
  'comfyui_negative_prompt_field': 'text',
  'comfyui_batch_size_node_id': '5',
  'comfyui_batch_size_field': 'batch_size',
  'comfyui_latent_width_field': 'width',   // 宽度
  'comfyui_latent_height_field': 'height', // 高度

  // --- 接口管理设置 ---
  'languageApis': [],
  'drawingApis': [],
  'videoApis': [],
  'activeLanguageApiId': null,
  'activeDrawingApiId': null,
  'activeVideoApiId': null,
  
  // --- 绘图标签设置 ---
  // 绘图质量
  'drawing_quality_tags': [
    {
      'id': 'system_quality',
      'name': '预设-高品质',
      'content': 'masterpiece, best quality, absurdres, ultra detailed, intricate details',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_quality_tag_id': 'system_quality', // 默认激活预设标签

  // 艺术家
  'drawing_artist_tags': [
    {
      'id': 'system_artist',
      'name': '预设-艺术家',
      'content': 'artist:DoReMi, artist:Hwansang, artist:Mx2j', // 艺术家标签通常是可选的
      'isSystemPreset': true,
    }
  ],
  'active_drawing_artist_tag_id': null,

  // 绘画风格
  'drawing_style_tags': [
    {
      'id': 'system_realistic_style',
      'name': '预设-写实风格',
      'content': 'realistic, photo-realistic, ultra-realistic, hyper-realistic',
      'isSystemPreset': true,
    },
    {
      'id': 'system_figurine_style',
      'name': '预设-手办风格',
      'content': 'figure, figurine, toy, vinyl figure',
      'isSystemPreset': true,
    },
    {
      'id': 'system_anime_style',
      'name': '预设-动漫风格',
      'content': 'anime style, anime screencap, 2D CG',
      'isSystemPreset': true,
    },
    {
      'id': 'system_ghibli_style',
      'name': '预设-吉普力风格',
      'content': 'Studio Ghibli style, Hayao Miyazaki style, Ghibli anime',
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

  // 负面标签
  'drawing_negative_tags': [
    {
      'id': 'system_negative',
      'name': '预设-通用负面',
      'content': 'lowres, bad anatomy, bad hands, extra digits, multiple views, fewer, extra, missing, text, error, worst quality, jpeg artifacts, low quality, watermark, unfinished, displeasing, oldest, early, chromatic aberration, signature, artistic error, username, scan',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_negative_tag_id': 'system_negative', // 负面标签通常默认激活

  // 角色设定
  'drawing_character_cards': [
    {
    'id': 'custom_character1',
    'name': '预设-黑长直少女',
    'characterName': 'girl',
    'identity': '1girl, solo',
    'appearance': 'long hair, straight hair, black hair, bangs, black eyes',
    'clothing': 'white long skirt, elegant dress',
    'other': '',
    'referenceImageUrl': null,
    'referenceImagePath': null,
    'isSystemPreset': true,
    },
    {
    'id': 'custom_character2',
    'name': '预设-可爱萝莉',
    'characterName': 'lily',
    'identity': '1girl, solo',
    'appearance': 'short hair, twintails, blonde hair, large eyes, blush, cute face',
    'clothing': 'frilly dress, puffy sleeves, ribbon, lolita fashion',
    'other': '',
    'referenceImageUrl': null,
    'referenceImagePath': null,
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