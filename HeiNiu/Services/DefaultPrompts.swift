/// 提示词库默认模板。
///
/// 本文件属于黑妞短剧（HeiNiu）工程，文档注释遵循 DocC 格式，
/// 可在 Xcode 中通过 Product → Build Documentation 浏览。

import Foundation

/// DefaultPrompts
///
/// `DefaultPrompts` 类型定义。
enum DefaultPrompts {
    /// 首次启动预置的多条提示词（按创作环节分组）
    static func seedItems() -> [PromptItem] {
        var items: [PromptItem] = []
        var order = 0

        /// add
        ///
        /// 执行 `add` 相关逻辑。
        func add(_ category: PromptCategory, _ name: String, _ template: String) {
            items.append(
                PromptItem(
                    category: category,
                    name: name,
                    template: template,
                    isBuiltIn: true,
                    sortOrder: order
                )
            )
            order += 1
        }

        // MARK: 剧本
        add(.script, "创作大纲", """
        你是一位短剧策划。根据创作简报，输出 3–5 个可拍的故事大纲备选。

        创作简报：
        {{brief}}

        产品信息：
        {{product}}

        风格参考：
        {{style}}

        每个大纲包含：一句话卖点、人物关系、核心冲突、结局走向、适拍时长。
        只输出大纲，不要额外解释。
        """)

        add(.script, "完整剧本", """
        你是一位短剧编剧。根据简报与产品信息，输出可直接拍摄的完整剧本。

        创作简报：
        {{brief}}

        产品信息：
        {{product}}

        要求：
        1. 明确人物、场景、冲突与情绪节奏
        2. 按场次划分，包含对白与动作提示
        3. 适合竖屏短视频，单集 1–3 分钟
        4. 只输出剧本正文
        """)

        add(.script, "对白润色", """
        你是一位对白编剧。在不改变剧情结构的前提下，润色下列剧本的对白，使其更口语、更有冲突感。

        剧本：
        {{source}}

        产品信息：
        {{product}}

        要求：保留场次结构；对白更短、更抓耳；只输出润色后的剧本。
        """)

        add(.script, "源文本改编", """
        你是一位短剧改编编剧。将源文本改编为适合短视频的短剧剧本。

        源文本：
        {{source}}

        产品信息：
        {{product}}

        要求：保留核心冲突与卖点；对白口语化；按场次输出；只输出剧本正文。
        """)

        // MARK: 分镜
        add(.storyboard, "分镜表", """
        你是一位短剧分镜导演。根据剧本输出分镜表。

        剧本：
        {{script}}

        产品信息：
        {{product}}

        目标时长：
        {{duration}}

        每个镜头输出：镜号、景别、画面描述、对白/旁白、运镜、预计秒数。
        使用 Markdown 列表。
        """)

        add(.storyboard, "镜头节奏优化", """
        你是一位剪辑向分镜顾问。在保持故事完整的前提下，压缩并优化镜头节奏。

        现有分镜：
        {{script}}

        产品信息：
        {{product}}

        指出可合并/可删的镜头，并给出优化后的分镜表。
        """)

        // MARK: 生图
        add(.image, "角色立绘", """
        为 AI 绘图模型生成角色立绘提示词（英文为主，可含中文专有名）。

        角色设定：
        {{subject}}

        风格：
        {{style}}

        产品/世界观：
        {{product}}

        输出一条高质量提示词，包含外貌、服装、姿态、光线、画质关键词；避免水印与文字。
        """)

        add(.image, "场景概念图", """
        为 AI 绘图模型生成场景概念图提示词。

        场景描述：
        {{subject}}

        氛围：
        {{style}}

        镜头感：
        {{camera}}

        产品/世界观：
        {{product}}

        输出一条提示词，强调空间层次、光影与材质。
        """)

        add(.image, "分镜参考图", """
        根据镜头描述生成分镜参考图提示词。

        镜头内容：
        {{subject}}

        景别/机位：
        {{camera}}

        风格：
        {{style}}

        输出适合 storyboard / cinematic still 的提示词。
        """)

        // MARK: 生视频
        add(.video, "镜头视频提示词", """
        你是一位 AI 视频提示词工程师。根据分镜生成可直接用于视频模型的英文提示词。

        分镜/镜头：
        {{shot}}

        整体分镜上下文：
        {{storyboard}}

        风格：
        {{style}}

        产品信息：
        {{product}}

        要求：包含主体、动作、运镜、光影、风格；避免水印字幕；按镜号输出。
        """)

        add(.video, "风格一致性约束", """
        基于已有镜头提示词，输出一套「风格锁定」附加提示，保证多镜头观感一致。

        参考镜头：
        {{shot}}

        目标风格：
        {{style}}

        输出可复用的风格段落（色调、镜头语言、人物一致性关键词）。
        """)

        // MARK: 角色
        add(.character, "角色卡提取", """
        从剧本中提取角色卡。

        剧本：
        {{script}}

        对每个角色输出：姓名、身份关系、外形、性格关键词、剧中作用。
        使用 Markdown 列表。
        """)

        add(.character, "外形描述强化", """
        将角色信息改写为适合生图/生视频的外形描述。

        角色名：
        {{name}}

        已有设定：
        {{traits}}

        输出：五官、发型、体态、服装、标志性道具、色彩关键词（中英可混）。
        """)

        // MARK: 场景
        add(.scene, "场景卡提取", """
        从剧本中提取场景卡。

        剧本：
        {{script}}

        每个场景输出：名称、时间、空间描述、关键道具、氛围关键词。
        """)

        add(.scene, "氛围与光影", """
        为指定场景生成氛围与光影描述，供分镜与生图使用。

        地点：
        {{location}}

        情绪：
        {{mood}}

        剧本上下文：
        {{script}}

        输出：时间、天气、主光源、色调、声音氛围、适合的景别建议。
        """)

        // MARK: 物品
        add(.item, "物品卡提取", """
        从剧本中提取关键物品/道具卡。

        剧本：
        {{script}}

        产品信息：
        {{product}}

        对每个物品输出：名称、类型（产品/道具/环境物件）、外观特征、材质与色彩、在剧中的作用、出现场次。
        使用 Markdown 列表。
        """)

        add(.item, "产品外观描述", """
        将产品或道具改写为适合生图/特写镜头的外观描述。

        物品名：
        {{name}}

        已有细节：
        {{details}}

        产品信息：
        {{product}}

        输出：形体、材质、颜色、Logo/细节、光泽、适合的展示角度与光线关键词（中英可混）。
        """)

        return items
    }

    /// 某分类下新建空白提示词的默认模板骨架
    static func blankTemplate(for category: PromptCategory) -> String {
        let vars = category.variableChips.joined(separator: "\n")
        return """
        你是一位短剧创作助手。请根据以下信息完成「\(category.displayName)」相关任务。

        \(vars.isEmpty ? "" : "可用输入：\n\(vars)\n")
        要求：
        1. …
        2. …
        3. 只输出结果，不要额外解释
        """
    }
}
