#include <xrt.h>
#include <experimental/xrt-next.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

constexpr unsigned kDeviceIndex = 2;
constexpr const char* kTargetBdf = "0000:9b:00.1";
constexpr const char* kIpName =
    "dlrm_f37x_rtl_kernel_stage2n_a10_v2:dlrm_a10_1";
constexpr unsigned kExpectedIpIndex = 0;

const unsigned char kExpectedUuidBytes[16] = {
    0xf7, 0xa2, 0x31, 0x17,
    0x52, 0x18,
    0x4f, 0xba,
    0xad, 0xb5,
    0xf0, 0x93, 0xb5, 0x96, 0xdf, 0x03
};

constexpr std::uint32_t A_MLP_VERSION = 0x004;
constexpr std::uint32_t A_INT_VERSION = 0x104;

constexpr std::uint32_t A_CTL = 0x180;
constexpr std::uint32_t A_VERSION = 0x184;
constexpr std::uint32_t A_RESULT_COUNT = 0x188;
constexpr std::uint32_t A_PHASE_COUNTS = 0x18C;
constexpr std::uint32_t A_DESC_INDEX = 0x190;
constexpr std::uint32_t A_DESC_WORD0 = 0x194;
constexpr std::uint32_t A_DESC_WORD1 = 0x198;
constexpr std::uint32_t A_DESC_WORD2 = 0x19C;
constexpr std::uint32_t A_ACT_BUFFER = 0x1A0;
constexpr std::uint32_t A_ACT_CHUNK = 0x1A4;
constexpr std::uint32_t A_ACT_MASK = 0x1A8;
constexpr std::uint32_t A_ACT_DATA0 = 0x1B0;
constexpr std::uint32_t A_ACT_DATA1 = 0x1B4;
constexpr std::uint32_t A_ACT_DATA2 = 0x1B8;
constexpr std::uint32_t A_ACT_DATA3 = 0x1BC;
constexpr std::uint32_t A_ACT_DATA4 = 0x1C0;
constexpr std::uint32_t A_ACT_DATA5 = 0x1C4;
constexpr std::uint32_t A_ACT_DATA6 = 0x1C8;
constexpr std::uint32_t A_ACT_DATA7 = 0x1CC;
constexpr std::uint32_t A_EMB_INDEX = 0x1D0;
constexpr std::uint32_t A_EMB_DATA0 = 0x1D4;
constexpr std::uint32_t A_EMB_DATA1 = 0x1D8;
constexpr std::uint32_t A_EMB_DATA2 = 0x1DC;
constexpr std::uint32_t A_EMB_DATA3 = 0x1E0;
constexpr std::uint32_t A_WEIGHT_ADDR = 0x1E4;
constexpr std::uint32_t A_WEIGHT_DATA = 0x1E8;
constexpr std::uint32_t A_BIAS_ADDR = 0x1EC;
constexpr std::uint32_t A_BIAS_DATA = 0x1F0;
constexpr std::uint32_t A_BOTTOM_CONFIG = 0x1F4;
constexpr std::uint32_t A_TOP_CONFIG = 0x1F8;
constexpr std::uint32_t A_PIPE_CONFIG = 0x1FC;
constexpr std::uint32_t A_RESULT_DATA = 0x200;
constexpr std::uint32_t A_RESULT_INDEX = 0x204;
constexpr std::uint32_t A_RESULT_META = 0x208;
constexpr std::uint32_t A_EMB_MASK = 0x20C;
constexpr std::uint32_t A_ERROR_CODE = 0x210;
constexpr std::uint32_t A_CONFIG_READY = 0x214;

constexpr std::uint32_t CMD_DESC = 0x0001;
constexpr std::uint32_t CMD_ACT = 0x0002;
constexpr std::uint32_t CMD_EMB = 0x0004;
constexpr std::uint32_t CMD_WEIGHT = 0x0008;
constexpr std::uint32_t CMD_BIAS = 0x0010;
constexpr std::uint32_t CMD_START = 0x0020;
constexpr std::uint32_t CMD_POP = 0x0040;
constexpr std::uint32_t CMD_ERROR_ACK = 0x0080;
constexpr std::uint32_t CMD_CLEAR_DONE = 0x0100;

constexpr std::uint32_t S_BUSY = 1u << 0;
constexpr std::uint32_t S_DONE = 1u << 1;
constexpr std::uint32_t S_VALID = 1u << 2;
constexpr std::uint32_t S_LAST = 1u << 3;
constexpr std::uint32_t S_CORE_ERROR = 1u << 4;
constexpr std::uint32_t S_WRAPPER_ERROR = 1u << 5;
constexpr std::uint32_t S_PENDING = 1u << 6;
constexpr std::uint32_t S_START_READY = 1u << 7;
constexpr std::uint32_t S_ANY_ERROR = 1u << 31;

constexpr std::uint32_t EXPECTED_MLP_VERSION = 0x00024701;
constexpr std::uint32_t EXPECTED_INT_VERSION = 0x00024E02;
constexpr std::uint32_t EXPECTED_PIPE_VERSION = 0x00024E11;

constexpr std::uint32_t BOTTOM_DESCRIPTOR_BASE = 0u;
constexpr std::uint32_t BOTTOM_LAYER_COUNT = 2u;
constexpr std::uint32_t TOP_DESCRIPTOR_BASE = 2u;
constexpr std::uint32_t TOP_LAYER_COUNT = 3u;
constexpr std::uint32_t EXPECTED_RESULT_TAG =
    TOP_DESCRIPTOR_BASE + TOP_LAYER_COUNT - 1u;

std::string hex32(std::uint32_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(8)
           << std::setfill('0') << value;
    return stream.str();
}

std::string uuid_string(const xuid_t uuid)
{
    static const char* digits = "0123456789abcdef";
    std::string result;
    result.reserve(36);

    for (int index = 0; index < 16; ++index) {
        if (index == 4 || index == 6 ||
            index == 8 || index == 10) {
            result.push_back('-');
        }
        result.push_back(digits[(uuid[index] >> 4) & 0xF]);
        result.push_back(digits[uuid[index] & 0xF]);
    }

    return result;
}

struct Descriptor {
    std::uint32_t word0;
    std::uint32_t word1;
    std::uint32_t word2;
};

Descriptor pack_descriptor(
    std::uint32_t input_dimension,
    std::uint32_t output_dimension,
    std::uint32_t weight_base,
    std::uint32_t bias_base,
    std::uint32_t output_shift,
    bool relu_enable)
{
    __uint128_t value = 0;
    value |= static_cast<__uint128_t>(input_dimension & 0x7FFu);
    value |= static_cast<__uint128_t>(output_dimension & 0x7FFu) << 11;
    value |= static_cast<__uint128_t>(weight_base) << 22;
    value |= static_cast<__uint128_t>(bias_base) << 54;
    value |= static_cast<__uint128_t>(output_shift & 0x3Fu) << 86;
    value |= static_cast<__uint128_t>(relu_enable ? 1u : 0u) << 92;

    Descriptor descriptor = {
        static_cast<std::uint32_t>(value),
        static_cast<std::uint32_t>(value >> 32),
        static_cast<std::uint32_t>(value >> 64)
    };
    return descriptor;
}

std::uint32_t pack_pair(std::int16_t low_value, std::int16_t high_value)
{
    return static_cast<std::uint32_t>(
               static_cast<std::uint16_t>(low_value)) |
           (static_cast<std::uint32_t>(
                static_cast<std::uint16_t>(high_value)) << 16);
}

class Hal
{
public:
    Hal()
    {
        std::memcpy(uuid_, kExpectedUuidBytes, sizeof(uuid_));

        handle_ = xclOpen(kDeviceIndex, nullptr, XCL_QUIET);
        if (!handle_) {
            throw std::runtime_error("xclOpen(index 2) failed");
        }

        const int index = xclIPName2Index(handle_, kIpName);
        if (index < 0) {
            throw std::runtime_error(
                std::string("xclIPName2Index failed for ") +
                kIpName + ": " + std::to_string(index));
        }

        ip_index_ = static_cast<unsigned>(index);

        std::cout
            << "HAL_DEVICE_INDEX=" << kDeviceIndex << "\n"
            << "HAL_TARGET_BDF=" << kTargetBdf << "\n"
            << "HAL_XCLBIN_UUID=" << uuid_string(uuid_) << "\n"
            << "HAL_IP_NAME=" << kIpName << "\n"
            << "HAL_IP_INDEX=" << ip_index_ << "\n";

        if (ip_index_ != kExpectedIpIndex) {
            throw std::runtime_error(
                "unexpected IP index: " +
                std::to_string(ip_index_));
        }

        const int context_result =
            xclOpenContext(
                handle_,
                uuid_,
                ip_index_,
                false);

        if (context_result != 0) {
            throw std::runtime_error(
                "xclOpenContext(exclusive) failed: " +
                std::to_string(context_result));
        }

        context_open_ = true;
        std::cout << "HAL_EXCLUSIVE_CONTEXT_OPEN=1\n";
    }

    ~Hal()
    {
        if (context_open_) {
            xclCloseContext(handle_, uuid_, ip_index_);
        }
        if (handle_) {
            xclClose(handle_);
        }
    }

    Hal(const Hal&) = delete;
    Hal& operator=(const Hal&) = delete;

    void write(std::uint32_t address, std::uint32_t value)
    {
        const int result =
            xclRegWrite(handle_, ip_index_, address, value);

        if (result != 0) {
            throw std::runtime_error(
                "xclRegWrite " + hex32(address) +
                " returned " + std::to_string(result));
        }
    }

    std::uint32_t read(std::uint32_t address)
    {
        std::uint32_t value = 0;
        const int result =
            xclRegRead(handle_, ip_index_, address, &value);

        if (result != 0) {
            throw std::runtime_error(
                "xclRegRead " + hex32(address) +
                " returned " + std::to_string(result));
        }

        return value;
    }

private:
    xclDeviceHandle handle_ = nullptr;
    xuid_t uuid_ = {};
    unsigned ip_index_ = 0;
    bool context_open_ = false;
};

void throw_on_error(Hal& hal, std::uint32_t status, const char* context)
{
    if (status & (S_ANY_ERROR | S_CORE_ERROR | S_WRAPPER_ERROR)) {
        const std::uint32_t error_code = hal.read(A_ERROR_CODE);
        throw std::runtime_error(
            std::string(context) +
            " status=" + hex32(status) +
            " error_code=" + hex32(error_code));
    }
}

template <typename Predicate>
std::uint32_t poll_status(
    Hal& hal,
    Predicate predicate,
    const char* description,
    int timeout_ms)
{
    const std::chrono::steady_clock::time_point deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(timeout_ms);

    std::uint32_t status = 0;

    while (std::chrono::steady_clock::now() < deadline) {
        status = hal.read(A_CTL);
        throw_on_error(hal, status, description);

        if (predicate(status)) {
            return status;
        }

        std::this_thread::sleep_for(
            std::chrono::microseconds(50));
    }

    throw std::runtime_error(
        std::string("timeout waiting for ") +
        description + " status=" + hex32(status));
}

void wait_command_idle(Hal& hal, const char* description)
{
    poll_status(
        hal,
        [](std::uint32_t status) {
            return (status & S_PENDING) == 0;
        },
        description,
        2000);
}

void acknowledge_existing_error(Hal& hal)
{
    std::uint32_t status = hal.read(A_CTL);

    if (status & (S_ANY_ERROR | S_CORE_ERROR | S_WRAPPER_ERROR)) {
        hal.write(A_CTL, CMD_ERROR_ACK);
        status = poll_status(
            hal,
            [](std::uint32_t value) {
                return
                    (value &
                     (S_ANY_ERROR |
                      S_CORE_ERROR |
                      S_WRAPPER_ERROR |
                      S_PENDING)) == 0;
            },
            "error acknowledgement",
            2000);
        std::cout
            << "PIPELINE_STALE_ERROR_ACKNOWLEDGED=1\n"
            << "PIPELINE_STATUS_AFTER_ERROR_ACK="
            << hex32(status) << "\n";
    }
}

void prepare_idle(Hal& hal, bool require_start_ready)
{
    acknowledge_existing_error(hal);

    std::uint32_t status = hal.read(A_CTL);

    // A final result held under host backpressure legitimately keeps BUSY
    // asserted until the Host issues POP. Release that stale result first.
    if (status & S_VALID) {
        const std::int32_t stale_result =
            static_cast<std::int32_t>(hal.read(A_RESULT_DATA));
        const std::uint32_t stale_index =
            hal.read(A_RESULT_INDEX) & 0x3Fu;
        const std::uint32_t stale_meta =
            hal.read(A_RESULT_META);
        const std::uint32_t stale_tag =
            (stale_meta >> 16) & 0xFFu;

        std::cout
            << "PIPELINE_STALE_RESULT_DETECTED=1\n"
            << "PIPELINE_STALE_STATUS="
            << hex32(status) << "\n"
            << "PIPELINE_STALE_RESULT="
            << stale_result << "\n"
            << "PIPELINE_STALE_INDEX="
            << stale_index << "\n"
            << "PIPELINE_STALE_META="
            << hex32(stale_meta) << "\n"
            << "PIPELINE_STALE_TAG="
            << stale_tag << "\n"
            << "PIPELINE_STALE_BUSY_HELD_FOR_BACKPRESSURE="
            << ((status & S_BUSY) ? 1 : 0) << "\n";

        hal.write(A_CTL, CMD_POP);
        status = poll_status(
            hal,
            [](std::uint32_t value) {
                return
                    (value &
                     (S_BUSY |
                      S_VALID |
                      S_PENDING)) == 0;
            },
            "stale backpressured result release",
            10000);

        std::cout
            << "PIPELINE_STALE_RESULT_POPPED=1\n"
            << "PIPELINE_STATUS_AFTER_STALE_POP="
            << hex32(status) << "\n";
    }

    // BUSY without VALID is an actual active/incomplete computation and must
    // not be disturbed automatically.
    if (status & S_BUSY) {
        throw std::runtime_error(
            "pipeline remains busy without a releasable result: " +
            hex32(status));
    }

    if (status & S_DONE) {
        hal.write(A_CTL, CMD_CLEAR_DONE);
        status = poll_status(
            hal,
            [](std::uint32_t value) {
                return
                    (value & (S_DONE | S_PENDING)) == 0;
            },
            "stale done clear",
            2000);
        std::cout
            << "PIPELINE_STALE_DONE_CLEARED=1\n"
            << "PIPELINE_STATUS_AFTER_DONE_CLEAR="
            << hex32(status) << "\n";
    }

    throw_on_error(hal, status, "prepare idle");

    if (status & (S_BUSY | S_VALID | S_PENDING | S_DONE)) {
        throw std::runtime_error(
            "pipeline is not idle after cleanup: " +
            hex32(status));
    }

    if (require_start_ready &&
        (status & S_START_READY) == 0) {
        throw std::runtime_error(
            "pipeline start is not ready after configured cleanup: " +
            hex32(status));
    }

    std::cout
        << "PIPELINE_IDLE_STATUS=" << hex32(status) << "\n"
        << "PIPELINE_IDLE_REQUIRE_START_READY="
        << (require_start_ready ? 1 : 0) << "\n";
}

void write_descriptor(
    Hal& hal,
    std::uint32_t index,
    const Descriptor& descriptor)
{
    hal.write(A_DESC_INDEX, index);
    hal.write(A_DESC_WORD0, descriptor.word0);
    hal.write(A_DESC_WORD1, descriptor.word1);
    hal.write(A_DESC_WORD2, descriptor.word2);
    hal.write(A_CTL, CMD_DESC);
    wait_command_idle(hal, "descriptor commit");
}

void write_weight(
    Hal& hal,
    std::uint32_t address,
    std::int8_t value)
{
    hal.write(A_WEIGHT_ADDR, address);
    hal.write(
        A_WEIGHT_DATA,
        static_cast<std::uint32_t>(
            static_cast<std::uint8_t>(value)));
    hal.write(A_CTL, CMD_WEIGHT);
    wait_command_idle(hal, "weight commit");
}

void write_bias(
    Hal& hal,
    std::uint32_t address,
    std::int32_t value)
{
    hal.write(A_BIAS_ADDR, address);
    hal.write(
        A_BIAS_DATA,
        static_cast<std::uint32_t>(value) & 0x00FFFFFFu);
    hal.write(A_CTL, CMD_BIAS);
    wait_command_idle(hal, "bias commit");
}

void write_embedding(
    Hal& hal,
    std::uint32_t index,
    const std::array<std::int16_t, 8>& values)
{
    hal.write(A_EMB_INDEX, index);
    hal.write(A_EMB_DATA0, pack_pair(values[0], values[1]));
    hal.write(A_EMB_DATA1, pack_pair(values[2], values[3]));
    hal.write(A_EMB_DATA2, pack_pair(values[4], values[5]));
    hal.write(A_EMB_DATA3, pack_pair(values[6], values[7]));
    hal.write(A_CTL, CMD_EMB);
    wait_command_idle(hal, "embedding commit");
}

void write_bottom_input(Hal& hal)
{
    hal.write(A_ACT_BUFFER, 0);
    hal.write(A_ACT_CHUNK, 0);
    hal.write(A_ACT_MASK, 0x000000FFu);
    hal.write(A_ACT_DATA0, pack_pair(1, 2));
    hal.write(A_ACT_DATA1, pack_pair(3, 4));
    hal.write(A_ACT_DATA2, pack_pair(5, 6));
    hal.write(A_ACT_DATA3, pack_pair(7, 8));
    hal.write(A_ACT_DATA4, 0);
    hal.write(A_ACT_DATA5, 0);
    hal.write(A_ACT_DATA6, 0);
    hal.write(A_ACT_DATA7, 0);
    hal.write(A_CTL, CMD_ACT);
    wait_command_idle(hal, "bottom activation commit");
}

void configure_model(Hal& hal)
{
    const std::array<Descriptor, 5> descriptors = {{
        pack_descriptor(8, 16, 0, 0, 0, true),
        pack_descriptor(16, 8, 128, 16, 0, true),
        pack_descriptor(18, 32, 256, 24, 0, true),
        pack_descriptor(32, 16, 832, 56, 0, true),
        pack_descriptor(16, 1, 1344, 72, 0, false)
    }};

    for (std::size_t index = 0; index < descriptors.size(); ++index) {
        write_descriptor(hal, static_cast<std::uint32_t>(index), descriptors[index]);
    }

    for (std::uint32_t address = 0; address < 1360; ++address) {
        write_weight(hal, address, 0);
        if ((address + 1u) % 256u == 0u || address == 1359u) {
            std::cout << "PIPELINE_WEIGHT_ZERO_PROGRESS=" << (address + 1u) << "/1360\n";
        }
    }

    for (std::uint32_t index = 0; index < 8; ++index) {
        write_weight(hal, index * 9u, 1);
        write_weight(hal, 128u + index * 17u, 1);
        write_weight(hal, 256u + index * 19u, 1);
        write_weight(hal, 832u + index * 33u, 1);
        write_weight(hal, 1344u + index, 1);
    }

    for (std::uint32_t address = 0; address < 73; ++address) {
        write_bias(hal, address, 0);
    }

    const std::array<std::int16_t, 8> zero_embedding = {{0,0,0,0,0,0,0,0}};
    for (std::uint32_t index = 0; index < 4; ++index) {
        write_embedding(hal, index, zero_embedding);
    }

    const std::uint32_t embedding_mask = hal.read(A_EMB_MASK);
    if ((embedding_mask & 0xFu) != 0xFu) {
        throw std::runtime_error("embedding mask mismatch: " + hex32(embedding_mask));
    }
    const std::uint32_t ready = hal.read(A_CONFIG_READY);
    if ((ready & 0x3Fu) != 0x3Fu) {
        throw std::runtime_error("configuration ready mismatch: " + hex32(ready));
    }

    std::cout
        << "PIPELINE_MODEL_CONFIGURATION_PASS=1\n"
        << "PIPELINE_DESCRIPTOR_COUNT=5\n"
        << "PIPELINE_WEIGHT_VALUES=1360\n"
        << "PIPELINE_BIAS_VALUES=73\n"
        << "PIPELINE_MODEL_SHAPE=8x16x8_interact18_32x16x1\n"
        << "PIPELINE_EMBEDDING_MASK=" << hex32(embedding_mask) << "\n"
        << "PIPELINE_CONFIG_READY=" << hex32(ready) << "\n";
}

void start_pipeline(Hal& hal)
{
    // Bottom: descriptor base 0, two layers, initial buffer 0.
    hal.write(
        A_BOTTOM_CONFIG,
        (BOTTOM_LAYER_COUNT << 8) | BOTTOM_DESCRIPTOR_BASE);

    // Top: descriptor base 2, three layers, input buffer 0.
    hal.write(
        A_TOP_CONFIG,
        (TOP_LAYER_COUNT << 8) | TOP_DESCRIPTOR_BASE);

    // Interaction output shift 0.
    hal.write(A_PIPE_CONFIG, 0u);

    const std::uint32_t start_ready_status = poll_status(
        hal,
        [](std::uint32_t status) {
            return
                (status & S_START_READY) != 0 &&
                (status & S_PENDING) == 0;
        },
        "configured pipeline start ready",
        2000);

    const std::uint32_t config_ready =
        hal.read(A_CONFIG_READY);

    if ((config_ready & 0x3Fu) != 0x3Fu) {
        throw std::runtime_error(
            "configuration lost readiness before start: " +
            hex32(config_ready));
    }

    std::cout
        << "PIPELINE_START_READY_STATUS="
        << hex32(start_ready_status) << "\n"
        << "PIPELINE_START_CONFIG_READY="
        << hex32(config_ready) << "\n";

    hal.write(A_CTL, CMD_START);
    wait_command_idle(hal, "pipeline start");
}

void run_once(
    Hal& hal,
    unsigned run_index,
    unsigned backpressure_reads)
{
    prepare_idle(hal, true);
    write_bottom_input(hal);
    start_pipeline(hal);

    std::uint32_t status = poll_status(
        hal,
        [](std::uint32_t value) {
            return (value & S_VALID) != 0;
        },
        "pipeline final result",
        10000);

    const std::int32_t result =
        static_cast<std::int32_t>(hal.read(A_RESULT_DATA));
    const std::uint32_t result_index =
        hal.read(A_RESULT_INDEX) & 0x3Fu;
    const std::uint32_t result_meta =
        hal.read(A_RESULT_META);
    const std::uint32_t result_tag =
        (result_meta >> 16) & 0xFFu;

    std::cout
        << "PIPELINE_RUN[" << run_index << "]_STATUS="
        << hex32(status) << "\n"
        << "PIPELINE_RUN[" << run_index << "]_RESULT="
        << result << "\n"
        << "PIPELINE_RUN[" << run_index << "]_INDEX="
        << result_index << "\n"
        << "PIPELINE_RUN[" << run_index << "]_META="
        << hex32(result_meta) << "\n"
        << "PIPELINE_RUN[" << run_index << "]_TAG="
        << result_tag << "\n"
        << "PIPELINE_RUN[" << run_index
        << "]_EXPECTED_FINAL_DESCRIPTOR_TAG="
        << EXPECTED_RESULT_TAG << "\n";

    if (result != 36) {
        throw std::runtime_error(
            "pipeline result mismatch: " +
            std::to_string(result));
    }

    if (result_index != 0) {
        throw std::runtime_error(
            "pipeline result index mismatch: " +
            std::to_string(result_index));
    }

    if ((result_meta & 0x3u) != 0x3u) {
        throw std::runtime_error(
            "pipeline result valid/last mismatch: " +
            hex32(result_meta));
    }

    if (result_tag != EXPECTED_RESULT_TAG) {
        throw std::runtime_error(
            "pipeline result tag mismatch: actual=" +
            std::to_string(result_tag) +
            " expected_final_descriptor_index=" +
            std::to_string(EXPECTED_RESULT_TAG));
    }

    for (unsigned read_index = 0;
         read_index < backpressure_reads;
         ++read_index) {
        const std::uint32_t held_status = hal.read(A_CTL);
        const std::int32_t held_result =
            static_cast<std::int32_t>(
                hal.read(A_RESULT_DATA));

        throw_on_error(
            hal,
            held_status,
            "result backpressure");

        if ((held_status & S_VALID) == 0 ||
            held_result != 36) {
            throw std::runtime_error(
                "result changed under host backpressure");
        }
    }

    hal.write(A_CTL, CMD_POP);

    status = poll_status(
        hal,
        [](std::uint32_t value) {
            return
                (value & S_DONE) != 0 &&
                (value & (S_BUSY | S_VALID | S_PENDING)) == 0;
        },
        "pipeline terminal done",
        10000);

    const std::uint32_t result_count =
        hal.read(A_RESULT_COUNT);
    const std::uint32_t phase_counts =
        hal.read(A_PHASE_COUNTS);

    const std::uint32_t bottom_count =
        (phase_counts >> 8) & 0xFu;
    const std::uint32_t interaction_count =
        (phase_counts >> 16) & 0x1Fu;

    std::cout
        << "PIPELINE_RUN[" << run_index << "]_TERMINAL_STATUS="
        << hex32(status) << "\n"
        << "PIPELINE_RUN[" << run_index << "]_RESULT_COUNT="
        << result_count << "\n"
        << "PIPELINE_RUN[" << run_index << "]_BOTTOM_COUNT="
        << bottom_count << "\n"
        << "PIPELINE_RUN[" << run_index << "]_INTERACTION_COUNT="
        << interaction_count << "\n"
        << "PIPELINE_RUN[" << run_index << "]_BACKPRESSURE_READS="
        << backpressure_reads << "\n";

    if (result_count != 1u) {
        throw std::runtime_error(
            "pipeline result count mismatch: " +
            std::to_string(result_count));
    }

    if (bottom_count != 8u) {
        throw std::runtime_error(
            "bottom result count mismatch: " +
            std::to_string(bottom_count));
    }

    if (interaction_count != 18u) {
        throw std::runtime_error(
            "interaction result count mismatch: " +
            std::to_string(interaction_count));
    }

    hal.write(A_CTL, CMD_CLEAR_DONE);

    poll_status(
        hal,
        [](std::uint32_t value) {
            return
                (value &
                 (S_BUSY |
                  S_DONE |
                  S_VALID |
                  S_PENDING |
                  S_ANY_ERROR |
                  S_CORE_ERROR |
                  S_WRAPPER_ERROR)) == 0;
        },
        "pipeline idle after clear done",
        2000);
}

}  // namespace

int main()
{
    try {
        std::cout
            << "Stage 2N-A10 F37X five-layer pipeline board smoke host v3\n"
            << "Access=xclOpenContext+xclRegRead+xclRegWrite\n";

        Hal hal;

        const std::uint32_t mlp_version =
            hal.read(A_MLP_VERSION);
        const std::uint32_t interaction_version =
            hal.read(A_INT_VERSION);
        const std::uint32_t pipeline_version =
            hal.read(A_VERSION);

        std::cout
            << "MLP_WINDOW_VERSION=" << hex32(mlp_version) << "\n"
            << "INTERACTION_WINDOW_VERSION="
            << hex32(interaction_version) << "\n"
            << "PIPELINE_WINDOW_VERSION="
            << hex32(pipeline_version) << "\n";

        if (mlp_version != EXPECTED_MLP_VERSION) {
            throw std::runtime_error(
                "legacy MLP version mismatch");
        }

        if (interaction_version != EXPECTED_INT_VERSION) {
            throw std::runtime_error(
                "interaction version mismatch");
        }

        if (pipeline_version != EXPECTED_PIPE_VERSION) {
            throw std::runtime_error(
                "pipeline version mismatch");
        }

        prepare_idle(hal, false);
        configure_model(hal);

        run_once(hal, 0, 0);
        run_once(hal, 1, 12);

        std::cout
            << "PIPELINE_DESCRIPTOR_CAPACITY=8\n"
            << "PIPELINE_WEIGHT_CAPACITY=2048\n"
            << "PIPELINE_BIAS_CAPACITY=128\n"
            << "PIPELINE_BOTTOM_DESCRIPTOR_BASE="
            << BOTTOM_DESCRIPTOR_BASE << "\n"
            << "PIPELINE_BOTTOM_LAYER_COUNT="
            << BOTTOM_LAYER_COUNT << "\n"
            << "PIPELINE_TOP_DESCRIPTOR_BASE="
            << TOP_DESCRIPTOR_BASE << "\n"
            << "PIPELINE_TOP_LAYER_COUNT="
            << TOP_LAYER_COUNT << "\n"
            << "PIPELINE_EXPECTED_RESULT_TAG="
            << EXPECTED_RESULT_TAG << "\n"
            << "PIPELINE_START_COMMANDS=2\n"
            << "PIPELINE_RESULT=36\n"
            << "BOTTOM_OUTPUTS=8\n"
            << "INTERACTION_OUTPUTS=18\n"
            << "FINAL_BACKPRESSURE_READS=12\n"
            << "STAGE2N_A10_PIPELINE_BOARD_SMOKE_V3_PASS "
            << "runs=2 final=36 bottom=8 interaction=18 "
            << "descriptors=5 weights=1360 biases=73\n";

        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr
            << "STAGE2N_A10_PIPELINE_BOARD_SMOKE_V3_FAILED: "
            << error.what() << "\n";
        return EXIT_FAILURE;
    }
}
