#!/usr/bin/env python3
"""
add-test-file.py — 把新测试文件注册进 QQPlayerTests target 的 pbxproj。

背景：QQPlayer 主 target 是 Xcode 16 的 PBXFileSystemSynchronizedRootGroup（新文件自动包含），
但 QQPlayerTests 是传统 PBXGroup，新增 .swift 测试文件必须手动改 pbxproj 4 处：
  1. PBXBuildFile 条目（Sources 编译）
  2. PBXFileReference 条目（文件引用）
  3. QQPlayerTests group 的 children（目录树显示）
  4. QQPlayerTests target 的 Sources build phase（编译进测试包）
本脚本自动完成这 4 处插入，生成唯一 24 位 hex ID，写回前用 plutil -lint 校验。

用法：
  python3 scripts/add-test-file.py <新测试文件名.swift>
  python3 scripts/add-test-file.py FooTests.swift --dry-run     # 只打印将要插入的内容，不写文件
  python3 scripts/add-test-file.py FooTests.swift --force       # 跳过"文件必须存在"检查
  python3 scripts/add-test-file.py FooTests.swift --pbxproj /tmp/test.pbxproj  # 指定 pbxproj（测试用）

安全设计：
  - 任何定位锚点找不到 → 报错退出（退出码 1），绝不写坏文件
  - 文件已注册（path = <name> 已存在）→ 幂等跳过，退出码 0
  - 写回前必须通过 plutil -lint，否则回滚并报错
"""
import argparse
import re
import subprocess
import sys
import uuid
from pathlib import Path

# 定位锚点
END_BUILDFILE = "/* End PBXBuildFile section */"
END_FILEREF = "/* End PBXFileReference section */"
TEST_GROUP_MARK = '/* QQPlayerTests */ = {'
TEST_PHASE_ANCHOR = "StableIdTests.swift in Sources */,"  # 测试 target Sources phase 特征行

INDENT_2 = "\t\t"
INDENT_4 = "\t\t\t\t"


def gen_unique_id(existing: set[str]) -> str:
    """生成 24 位大写 hex ID，保证不与现有 ID 冲突。"""
    while True:
        candidate = uuid.uuid4().hex[:24].upper()
        if candidate not in existing:
            return candidate


def collect_existing_ids(lines: list[str]) -> set[str]:
    """收集 pbxproj 中所有已用的 24 位 hex ID。"""
    ids = set()
    for line in lines:
        for m in re.finditer(r"\b([0-9A-F]{24})\b", line):
            ids.add(m.group(1))
    return ids


def find_line_index(lines: list[str], needle: str, start: int = 0) -> int:
    """找精确行（strip 后相等），找不到返回 -1。"""
    for i in range(start, len(lines)):
        if lines[i].strip() == needle:
            return i
    return -1


def find_test_group_children_end(lines: list[str]) -> int:
    """
    定位 QQPlayerTests PBXGroup 的 children 列表结束行（`\t\t\t);`）。
    规则：找到 `/* QQPlayerTests */ = {` 且后续有 `isa = PBXGroup;` 的块，
    取其 children = ( ... ); 的结束行。
    """
    i = 0
    while i < len(lines):
        if TEST_GROUP_MARK in lines[i]:
            # 向后确认是 PBXGroup（而不是 PBXNativeTarget）
            j = i + 1
            while j < len(lines) and j <= i + 6:
                if "isa = PBXGroup;" in lines[j]:
                    # 找 children = ( 起始
                    k = j + 1
                    while k < len(lines) and k <= j + 40:
                        if "children = (" in lines[k]:
                            # 找列表结束 `\t\t\t);`（3 tab + );）
                            end = k + 1
                            while end < len(lines):
                                if re.match(r"^\t{3}\);$", lines[end]):
                                    return end
                                end += 1
                            return -1
                        k += 1
                    return -1
                if "isa = " in lines[j] and "PBXGroup" not in lines[j]:
                    break  # 是别的 isa，跳过
                j += 1
        i += 1
    return -1


def find_test_sources_phase_end(lines: list[str]) -> int:
    """
    定位 QQPlayerTests target 的 Sources build phase files 列表结束行。
    规则：找含 StableIdTests.swift in Sources 的行，向后找第一个 `\t\t\t);`。
    """
    anchor = -1
    for i, line in enumerate(lines):
        if TEST_PHASE_ANCHOR in line:
            anchor = i
            break
    if anchor == -1:
        return -1
    end = anchor + 1
    while end < len(lines):
        if re.match(r"^\t{3}\);$", lines[end]):
            return end
        end += 1
    return -1


def main() -> int:
    parser = argparse.ArgumentParser(description="注册新测试文件到 QQPlayerTests target 的 pbxproj（4 处）")
    parser.add_argument("filename", help="新测试文件名，如 FooTests.swift")
    parser.add_argument("--pbxproj", default="QQPlayer.xcodeproj/project.pbxproj", help="pbxproj 路径（默认 QQPlayer.xcodeproj/project.pbxproj）")
    parser.add_argument("--dry-run", action="store_true", help="只打印将插入的内容，不写文件")
    parser.add_argument("--force", action="store_true", help="跳过'源文件必须存在'检查")
    args = parser.parse_args()

    name = args.filename
    if not name.endswith(".swift") or "/" in name:
        print(f"❌ 文件名必须是 QQPlayerTests/ 下的 .swift 文件名（如 FooTests.swift），收到: {name}", file=sys.stderr)
        return 1

    pbxproj = Path(args.pbxproj)
    if not pbxproj.exists():
        print(f"❌ pbxproj 不存在: {pbxproj}", file=sys.stderr)
        return 1

    # 源文件存在检查（防手误）
    if not args.force:
        src = pbxproj.parent.parent / "QQPlayerTests" / name
        if not src.exists():
            print(f"❌ 源文件不存在: {src}（如确要注册请加 --force）", file=sys.stderr)
            return 1

    lines = pbxproj.read_text(encoding="utf-8").splitlines(keepends=True)

    # 幂等：已注册则跳过
    if any(f"path = {name};" in line for line in lines):
        print(f"ℹ️  {name} 已注册在 {pbxproj}，无需操作")
        return 0

    # 定位 4 个插入点
    idx_buildfile = find_line_index(lines, END_BUILDFILE)
    idx_fileref = find_line_index(lines, END_FILEREF)
    idx_group = find_test_group_children_end(lines)
    idx_phase = find_test_sources_phase_end(lines)

    missing = []
    if idx_buildfile == -1:
        missing.append(END_BUILDFILE)
    if idx_fileref == -1:
        missing.append(END_FILEREF)
    if idx_group == -1:
        missing.append("QQPlayerTests PBXGroup children 列表")
    if idx_phase == -1:
        missing.append("QQPlayerTests Sources build phase files 列表")
    if missing:
        print(f"❌ 定位锚点失败（{', '.join(missing)}），拒绝写文件。pbxproj 可能不是预期结构。", file=sys.stderr)
        return 1

    # 生成唯一 ID
    existing = collect_existing_ids(lines)
    file_ref_id = gen_unique_id(existing)
    build_file_id = gen_unique_id(existing | {file_ref_id})

    build_file_line = f"{INDENT_2}{build_file_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {name} */; }};\n"
    file_ref_line = f"{INDENT_2}{file_ref_id} /* {name} */ = {{isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n"
    group_child_line = f"{INDENT_4}{file_ref_id} /* {name} */,\n"
    phase_file_line = f"{INDENT_4}{build_file_id} /* {name} in Sources */,\n"

    print(f"将向 {pbxproj} 注册 {name}：")
    print(f"  ① PBXBuildFile:     {build_file_id}（插在 {END_BUILDFILE} 前）")
    print(f"  ② PBXFileReference: {file_ref_id}（插在 {END_FILEREF} 前）")
    print(f"  ③ QQPlayerTests group children（第 {idx_group + 1} 行前）")
    print(f"  ④ QQPlayerTests Sources phase files（第 {idx_phase + 1} 行前）")

    if args.dry_run:
        print("\n[dry-run] 将插入：")
        for label, line in [("①", build_file_line), ("②", file_ref_line), ("③", group_child_line), ("④", phase_file_line)]:
            print(f"  {label} {line.rstrip()}")
        return 0

    # 从后往前插，避免行号漂移（idx 顺序: buildfile < fileref < group < phase）
    insertions = [
        (idx_phase, phase_file_line),
        (idx_group, group_child_line),
        (idx_fileref, file_ref_line),
        (idx_buildfile, build_file_line),
    ]
    for idx, line in sorted(insertions, key=lambda x: x[0], reverse=True):
        lines.insert(idx, line)

    new_content = "".join(lines)

    # plutil 校验通过才写回
    tmp = pbxproj.with_suffix(".pbxproj.tmp")
    tmp.write_text(new_content, encoding="utf-8")
    result = subprocess.run(["plutil", "-lint", str(tmp)], capture_output=True, text=True)
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        print(f"❌ plutil -lint 校验失败，已回滚（pbxproj 未改动）：\n{result.stdout}{result.stderr}", file=sys.stderr)
        return 1

    tmp.replace(pbxproj)
    print(f"✅ {name} 已注册（4 处），plutil -lint 通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
