#!/bin/bash

# 云效工作项CRUD操作测试脚本
# 测试所有工作项操作的功能完整性

# 获取脚本目录并引入通用函数
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/workitem-common.sh"

# =============================================================================
# 测试配置
# =============================================================================

# 测试数据
TEST_PREFIX="测试工作项"
TEST_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEST_WORKITEM_TITLE="${TEST_PREFIX}_${TEST_TIMESTAMP}"
TEST_WORKITEM_DESCRIPTION="这是一个用于测试CRUD操作的工作项，创建时间：$(date)"

# 测试结果记录
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# 临时文件
TEMP_DIR="/tmp/yunxiao_test_$$"
TEST_LOG="$TEMP_DIR/test.log"
BACKUP_FILE="$TEMP_DIR/backup.json"

# =============================================================================
# 测试工具函数
# =============================================================================

# 初始化测试环境
setup_test_environment() {
    echo "=== 云效工作项CRUD测试 ==="
    echo "测试时间: $(date)"
    echo "测试前缀: $TEST_PREFIX"
    echo ""

    # 创建临时目录
    mkdir -p "$TEMP_DIR"

    # 初始化日志
    echo "测试开始: $(date)" > "$TEST_LOG"

    # 检查依赖
    if ! check_workitem_dependencies; then
        echo "❌ 依赖检查失败，跳过测试"
        exit 1
    fi

    echo "✅ 测试环境初始化完成"
    echo ""
}

# 清理测试环境
cleanup_test_environment() {
    echo ""
    echo "=== 清理测试环境 ==="

    # 删除临时文件
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo "✅ 临时文件已清理"
    fi

    echo "✅ 测试环境清理完成"
}

# 记录测试结果
record_test_result() {
    local test_name="$1"
    local result="$2"  # "PASS" or "FAIL"
    local details="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "✅ $test_name"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "❌ $test_name: $details"
    fi

    TEST_RESULTS+=("$result: $test_name - $details")
    echo "$(date): $result: $test_name - $details" >> "$TEST_LOG"
}

# 运行命令并检查结果
run_test_command() {
    local test_name="$1"
    local command="$2"
    local expected_exit_code="${3:-0}"

    echo -n "测试 $test_name... "

    local output
    local exit_code

    # 执行命令
    output=$(eval "$command" 2>&1)
    exit_code=$?

    # 检查退出码
    if [ $exit_code -eq $expected_exit_code ]; then
        record_test_result "$test_name" "PASS" "退出码: $exit_code"
        return 0
    else
        record_test_result "$test_name" "FAIL" "期望退出码: $expected_exit_code, 实际退出码: $exit_code"
        echo "命令输出: $output" >> "$TEST_LOG"
        return 1
    fi
}

# =============================================================================
# 创建操作测试
# =============================================================================

test_create_workitem() {
    echo "=== 测试工作项创建 ==="

    # 测试基本创建功能
    run_test_command "创建任务工作项" \
        "$SCRIPT_DIR/create-workitem.sh -n task '$TEST_WORKITEM_TITLE' '$TEST_WORKITEM_DESCRIPTION'"

    # 测试带优先级的创建
    run_test_command "创建高优先级需求" \
        "$SCRIPT_DIR/create-workitem.sh -n -p 高 requirement '高优先级需求' '重要的业务需求'"

    # 测试模板创建
    run_test_command "使用模板创建缺陷" \
        "$SCRIPT_DIR/create-workitem.sh -n -t '$SCRIPT_DIR/workitem-templates/bug.json' bug '测试缺陷' '发现的问题'"

    # 测试批量创建（干运行）
    echo '{"type":"task","title":"批量任务1","description":"批量创建测试"}' | \
        run_test_command "批量创建工作项" \
        "$SCRIPT_DIR/create-workitem.sh -n --batch"

    # 测试参数验证
    run_test_command "创建时类型验证" \
        "$SCRIPT_DIR/create-workitem.sh -n invalid_type '测试标题' '测试描述'" 1

    run_test_command "创建时标题验证" \
        "$SCRIPT_DIR/create-workitem.sh -n task '短' '测试描述'" 1

    echo ""
}

# =============================================================================
# 查询操作测试
# =============================================================================

test_get_workitem() {
    echo "=== 测试工作项查询 ==="

    # 测试ID验证
    run_test_command "查询时ID验证" \
        "$SCRIPT_DIR/get-workitem.sh invalid_id" 1

    # 测试输出格式
    run_test_command "JSON输出格式" \
        "$SCRIPT_DIR/get-workitem.sh -o json 12345"

    run_test_command "表格输出格式" \
        "$SCRIPT_DIR/get-workitem.sh -o table 12345"

    run_test_command "摘要输出格式" \
        "$SCRIPT_DIR/get-workitem.sh -o summary 12345"

    # 测试字段过滤
    run_test_command "字段过滤" \
        "$SCRIPT_DIR/get-workitem.sh -f 'id,title,status' 12345"

    # 测试批量查询
    echo "12345" | run_test_command "批量查询" \
        "$SCRIPT_DIR/get-workitem.sh --batch"

    echo ""
}

# =============================================================================
# 列表操作测试
# =============================================================================

test_list_workitems() {
    echo "=== 测试工作项列表 ==="

    # 测试基本列表
    run_test_command "基本列表查询" \
        "$SCRIPT_DIR/list-workitems.sh --page 1 --size 5"

    # 测试过滤器
    run_test_command "按类型过滤" \
        "$SCRIPT_DIR/list-workitems.sh -t task --size 5"

    run_test_command "按状态过滤" \
        "$SCRIPT_DIR/list-workitems.sh -s 进行中 --size 5"

    run_test_command "按优先级过滤" \
        "$SCRIPT_DIR/list-workitems.sh -p 高 --size 5"

    # 测试排序
    run_test_command "按创建时间排序" \
        "$SCRIPT_DIR/list-workitems.sh --sort created_time --order asc --size 5"

    # 测试输出格式
    run_test_command "列表JSON输出" \
        "$SCRIPT_DIR/list-workitems.sh -o json --size 3"

    run_test_command "列表摘要输出" \
        "$SCRIPT_DIR/list-workitems.sh -o summary --size 3"

    run_test_command "仅计数输出" \
        "$SCRIPT_DIR/list-workitems.sh -o count"

    # 测试参数验证
    run_test_command "无效类型过滤" \
        "$SCRIPT_DIR/list-workitems.sh -t invalid_type" 1

    run_test_command "无效页码" \
        "$SCRIPT_DIR/list-workitems.sh --page 0" 1

    echo ""
}

# =============================================================================
# 更新操作测试
# =============================================================================

test_update_workitem() {
    echo "=== 测试工作项更新 ==="

    # 测试基本更新（干运行）
    run_test_command "基本字段更新" \
        "$SCRIPT_DIR/update-workitem.sh -n 12345 title='更新后的标题'"

    # 测试多字段更新
    run_test_command "多字段更新" \
        "$SCRIPT_DIR/update-workitem.sh -n 12345 status=进行中 priority=高"

    # 测试JSON更新
    run_test_command "JSON格式更新" \
        "$SCRIPT_DIR/update-workitem.sh -n -j '{\"title\":\"JSON更新标题\",\"status\":\"已完成\"}' 12345"

    # 测试文件更新
    echo '{"title":"文件更新标题","description":"从文件更新"}' > "$TEMP_DIR/update.json"
    run_test_command "文件格式更新" \
        "$SCRIPT_DIR/update-workitem.sh -n -f '$TEMP_DIR/update.json' 12345"

    # 测试参数验证
    run_test_command "更新时ID验证" \
        "$SCRIPT_DIR/update-workitem.sh -n invalid_id title='测试'" 1

    run_test_command "更新时标题验证" \
        "$SCRIPT_DIR/update-workitem.sh -n 12345 title='短'" 1

    echo ""
}

# =============================================================================
# 删除操作测试
# =============================================================================

test_delete_workitem() {
    echo "=== 测试工作项删除 ==="

    # 测试软删除（干运行）
    run_test_command "软删除工作项" \
        "$SCRIPT_DIR/delete-workitem.sh -n 12345"

    # 测试硬删除（干运行）
    run_test_command "硬删除工作项" \
        "$SCRIPT_DIR/delete-workitem.sh -n --hard 12345"

    # 测试归档（干运行）
    run_test_command "归档工作项" \
        "$SCRIPT_DIR/delete-workitem.sh -n --archive 12345"

    # 测试备份功能
    run_test_command "删除时备份" \
        "$SCRIPT_DIR/delete-workitem.sh -n --backup '$BACKUP_FILE' 12345"

    # 测试批量删除
    echo "12345" | run_test_command "批量删除" \
        "$SCRIPT_DIR/delete-workitem.sh -n --batch"

    # 测试参数验证
    run_test_command "删除时ID验证" \
        "$SCRIPT_DIR/delete-workitem.sh -n invalid_id" 1

    echo ""
}

# =============================================================================
# 集成测试
# =============================================================================

test_crud_integration() {
    echo "=== 测试CRUD集成流程 ==="

    # 注意：这些是集成测试，可能需要实际的MCP连接
    # 在没有真实环境时，这些测试会失败，但可以验证脚本逻辑

    echo "注意：以下集成测试需要真实的云效MCP连接"

    # 创建 -> 查询 -> 更新 -> 删除 的完整流程
    # 由于没有真实环境，这里只做参数验证测试

    record_test_result "CRUD集成测试" "SKIP" "需要真实的MCP环境"

    echo ""
}

# =============================================================================
# 性能测试
# =============================================================================

test_performance() {
    echo "=== 测试性能 ==="

    # 测试命令执行时间
    local start_time end_time duration

    start_time=$(date +%s.%N)
    "$SCRIPT_DIR/create-workitem.sh" -n task "性能测试" "测试命令执行速度" >/dev/null 2>&1
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")

    if [ "$duration" != "N/A" ] && (( $(echo "$duration < 2.0" | bc -l) )); then
        record_test_result "创建命令性能" "PASS" "执行时间: ${duration}s"
    else
        record_test_result "创建命令性能" "FAIL" "执行时间过长: ${duration}s"
    fi

    echo ""
}

# =============================================================================
# 错误处理测试
# =============================================================================

test_error_handling() {
    echo "=== 测试错误处理 ==="

    # 测试无效参数
    run_test_command "无效命令选项" \
        "$SCRIPT_DIR/create-workitem.sh --invalid-option" 1

    # 测试缺少必需参数
    run_test_command "缺少工作项类型" \
        "$SCRIPT_DIR/create-workitem.sh" 1

    # 测试无效模板文件
    run_test_command "无效模板文件" \
        "$SCRIPT_DIR/create-workitem.sh -t '/nonexistent/template.json' task '测试' '测试'" 1

    # 测试无效JSON
    run_test_command "无效JSON格式" \
        "$SCRIPT_DIR/update-workitem.sh -j 'invalid{json}' 12345" 1

    echo ""
}

# =============================================================================
# 主测试函数
# =============================================================================

run_all_tests() {
    setup_test_environment

    # 设置错误处理
    set +e  # 允许命令失败，继续执行测试

    # 运行所有测试
    test_create_workitem
    test_get_workitem
    test_list_workitems
    test_update_workitem
    test_delete_workitem
    test_crud_integration
    test_performance
    test_error_handling

    # 输出测试总结
    show_test_summary

    cleanup_test_environment

    # 根据测试结果设置退出码
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# 显示测试总结
show_test_summary() {
    echo "=========================="
    echo "测试总结"
    echo "=========================="
    echo "总测试数: $TOTAL_TESTS"
    echo "通过: $PASSED_TESTS"
    echo "失败: $FAILED_TESTS"
    echo "成功率: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo ""

    if [ $FAILED_TESTS -gt 0 ]; then
        echo "失败的测试:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                echo "  $result"
            fi
        done
        echo ""
    fi

    echo "详细日志: $TEST_LOG"
    echo "=========================="
}

# 显示帮助信息
show_help() {
    cat << EOF
云效工作项CRUD测试工具

用法:
    $0 [选项]

选项:
    --create     仅测试创建功能
    --read       仅测试查询功能
    --update     仅测试更新功能
    --delete     仅测试删除功能
    --integration 仅测试集成流程
    --performance 仅测试性能
    --errors     仅测试错误处理
    -v, --verbose 详细输出
    -h, --help   显示此帮助信息

示例:
    $0                # 运行所有测试
    $0 --create       # 仅测试创建功能
    $0 --verbose      # 详细输出模式

EOF
}

# =============================================================================
# 主程序
# =============================================================================

main() {
    local test_mode="all"

    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --create)
                test_mode="create"
                shift
                ;;
            --read)
                test_mode="read"
                shift
                ;;
            --update)
                test_mode="update"
                shift
                ;;
            --delete)
                test_mode="delete"
                shift
                ;;
            --integration)
                test_mode="integration"
                shift
                ;;
            --performance)
                test_mode="performance"
                shift
                ;;
            --errors)
                test_mode="errors"
                shift
                ;;
            -v|--verbose)
                export YUNXIAO_DEBUG=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "无效选项: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done

    # 根据模式运行测试
    case "$test_mode" in
        all)
            run_all_tests
            ;;
        create)
            setup_test_environment
            test_create_workitem
            show_test_summary
            cleanup_test_environment
            ;;
        read)
            setup_test_environment
            test_get_workitem
            test_list_workitems
            show_test_summary
            cleanup_test_environment
            ;;
        update)
            setup_test_environment
            test_update_workitem
            show_test_summary
            cleanup_test_environment
            ;;
        delete)
            setup_test_environment
            test_delete_workitem
            show_test_summary
            cleanup_test_environment
            ;;
        integration)
            setup_test_environment
            test_crud_integration
            show_test_summary
            cleanup_test_environment
            ;;
        performance)
            setup_test_environment
            test_performance
            show_test_summary
            cleanup_test_environment
            ;;
        errors)
            setup_test_environment
            test_error_handling
            show_test_summary
            cleanup_test_environment
            ;;
    esac
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi