# 提示模板

```text
任务：<一句话说明任务>

模式：
$ltp-task-router

范围：

只允许：
- <file1>
- <file2>

禁止：
- 其它全部文件
- ROADMAP / ARCH / CHANGELOG，除非任务是 Level 3

目标：
- 最小 diff
- 不重构
- 保持行为不变

上下文：
<只放错误片段或功能片段>

输出：
- 已改文件
- 关键行为变化
- 验证结果
- 对抗式审查
```
