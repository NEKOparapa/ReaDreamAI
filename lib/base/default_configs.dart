// lib/base/default_configs.dart

/// 全局应用默认配置
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

  // --- 翻译设置 --- 
  'translation_tokens': 4000,
  'translation_source_lang': 'English',
  'translation_target_lang': '中文',

  // --- ComfyUI节点设置 ---
  'comfyui_workflow_type': 'WAI+illustrious的API工作流', // 默认工作流类型
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
  'activeLanguageApiId': null,
  'activeDrawingApiId': null,

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
      'id': 'system_style',
      'name': '预设-动漫风格',
      'content': 'anime style, anime screencap, game CG',
      'isSystemPreset': true,
    }
  ],
  'active_drawing_style_tag_id': 'system_style', // 默认激活一个

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
      'id': 'system_character',
      'name': '预设-女性角色',
      'characterName': 'honey',
      'identity': '1girl, solo',
      'appearance': 'long hair, blue eyes, beautiful detailed eyes',
      'clothing': 'white dress, strapless dress',
      'other': '',
      'referenceImageUrl': null, // 新增
      'referenceImagePath': null, // 新增
      'isSystemPreset': true,
    }
  ],
  'active_drawing_character_card_ids': [], // 角色默认不激活
};