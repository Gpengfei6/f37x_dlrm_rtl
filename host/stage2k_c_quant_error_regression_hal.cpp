#include <xrt.h>
#include <experimental/xrt-next.h>

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr unsigned int kDeviceIndex = 2;
constexpr const char* kTargetBdf = "0000:9b:00.1";
constexpr const char* kIpName =
    "dlrm_f37x_rtl_kernel:dlrm_f37x_rtl_kernel_1";
constexpr unsigned int kExpectedIpIndex = 0;

const unsigned char kExpectedUuidBytes[16] = {
    0x49, 0xdb, 0xac, 0x1d,
    0x80, 0x53,
    0x4b, 0xd3,
    0x9d, 0x1a,
    0x54, 0xf0, 0x5a, 0x54, 0x14, 0xd9
};

constexpr std::uint32_t ADDR_CONTROL_STATUS = 0x000;
constexpr std::uint32_t ADDR_VERSION = 0x004;
constexpr std::uint32_t ADDR_RESULT_COUNT = 0x008;
constexpr std::uint32_t ADDR_LAYER_COUNT = 0x010;
constexpr std::uint32_t ADDR_INITIAL_BUFFER = 0x014;
constexpr std::uint32_t ADDR_DESC_INDEX = 0x020;
constexpr std::uint32_t ADDR_DESC_WORD0 = 0x024;
constexpr std::uint32_t ADDR_DESC_WORD1 = 0x028;
constexpr std::uint32_t ADDR_DESC_WORD2 = 0x02C;
constexpr std::uint32_t ADDR_ACT_BUFFER = 0x040;
constexpr std::uint32_t ADDR_ACT_CHUNK_INDEX = 0x044;
constexpr std::uint32_t ADDR_ACT_LANE_MASK = 0x048;
constexpr std::uint32_t ADDR_ACT_DATA0 = 0x050;
constexpr std::uint32_t ADDR_ACT_DATA1 = 0x054;
constexpr std::uint32_t ADDR_ACT_DATA2 = 0x058;
constexpr std::uint32_t ADDR_ACT_DATA3 = 0x05C;
constexpr std::uint32_t ADDR_ACT_DATA4 = 0x060;
constexpr std::uint32_t ADDR_ACT_DATA5 = 0x064;
constexpr std::uint32_t ADDR_ACT_DATA6 = 0x068;
constexpr std::uint32_t ADDR_ACT_DATA7 = 0x06C;
constexpr std::uint32_t ADDR_WEIGHT_ADDRESS = 0x080;
constexpr std::uint32_t ADDR_WEIGHT_DATA = 0x084;
constexpr std::uint32_t ADDR_BIAS_ADDRESS = 0x090;
constexpr std::uint32_t ADDR_BIAS_DATA = 0x094;
constexpr std::uint32_t ADDR_RESULT_DATA = 0x0A0;
constexpr std::uint32_t ADDR_RESULT_INDEX = 0x0A4;
constexpr std::uint32_t ADDR_RESULT_META = 0x0A8;

constexpr std::uint32_t CMD_START = 0x00000001;
constexpr std::uint32_t CMD_DESC_COMMIT = 0x00000002;
constexpr std::uint32_t CMD_ACT_COMMIT = 0x00000004;
constexpr std::uint32_t CMD_WEIGHT_COMMIT = 0x00000008;
constexpr std::uint32_t CMD_BIAS_COMMIT = 0x00000010;
constexpr std::uint32_t CMD_RESULT_POP = 0x00000020;
constexpr std::uint32_t CMD_ERROR_ACK = 0x00000040;
constexpr std::uint32_t CMD_CLEAR_DONE = 0x00000080;

constexpr std::uint32_t STATUS_BUSY = 1u << 0;
constexpr std::uint32_t STATUS_DONE = 1u << 1;
constexpr std::uint32_t STATUS_RESULT_VALID = 1u << 2;
constexpr std::uint32_t STATUS_CORE_ERROR = 1u << 4;
constexpr std::uint32_t STATUS_WRAPPER_ERROR = 1u << 5;
constexpr std::uint32_t STATUS_FINAL_BUFFER = 1u << 6;
constexpr std::uint32_t STATUS_COMMAND_PENDING = 1u << 7;

constexpr std::uint32_t EXPECTED_VERSION = 0x00024701;
constexpr std::uint32_t MAX_LAYERS = 4;
constexpr std::uint32_t MAX_WEIGHT_VALUES = 65536;
constexpr std::uint32_t MAX_BIAS_VALUES = 1024;
constexpr std::uint32_t ACC_WIDTH = 48;

constexpr std::uint32_t ERROR_BAD_LAYER_COUNT = 1;
constexpr std::uint32_t ERROR_MISSING_DESCRIPTOR = 2;
constexpr std::uint32_t ERROR_BAD_DIMENSION = 3;
constexpr std::uint32_t ERROR_DIMENSION_MISMATCH = 4;
constexpr std::uint32_t ERROR_WEIGHT_RANGE = 5;
constexpr std::uint32_t ERROR_BIAS_RANGE = 6;
constexpr std::uint32_t ERROR_BAD_SHIFT = 7;

std::string hex32(std::uint32_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(8) << std::setfill('0')
           << value;
    return stream.str();
}

std::string uuid_to_string(const xuid_t uuid)
{
    static const char* digits = "0123456789abcdef";
    std::string text;
    text.reserve(36);

    for (int index = 0; index < 16; ++index) {
        if (index == 4 || index == 6 || index == 8 || index == 10) {
            text.push_back('-');
        }

        const unsigned char byte = uuid[index];
        text.push_back(digits[(byte >> 4) & 0xFu]);
        text.push_back(digits[byte & 0xFu]);
    }

    return text;
}

std::string error_name(std::uint32_t code)
{
    switch (code) {
    case ERROR_BAD_LAYER_COUNT:
        return "ERROR_BAD_LAYER_COUNT";
    case ERROR_MISSING_DESCRIPTOR:
        return "ERROR_MISSING_DESCRIPTOR";
    case ERROR_BAD_DIMENSION:
        return "ERROR_BAD_DIMENSION";
    case ERROR_DIMENSION_MISMATCH:
        return "ERROR_DIMENSION_MISMATCH";
    case ERROR_WEIGHT_RANGE:
        return "ERROR_WEIGHT_RANGE";
    case ERROR_BIAS_RANGE:
        return "ERROR_BIAS_RANGE";
    case ERROR_BAD_SHIFT:
        return "ERROR_BAD_SHIFT";
    default:
        return "ERROR_UNKNOWN";
    }
}

struct DescriptorWords {
    std::uint32_t word0;
    std::uint32_t word1;
    std::uint32_t word2;
};

DescriptorWords pack_descriptor(
    std::uint32_t in_dim,
    std::uint32_t out_dim,
    std::uint32_t weight_base,
    std::uint32_t bias_base,
    std::uint32_t output_shift,
    bool relu_enable)
{
    __uint128_t value = 0;
    value |= static_cast<__uint128_t>(in_dim & 0x7FFu);
    value |= static_cast<__uint128_t>(out_dim & 0x7FFu) << 11;
    value |= static_cast<__uint128_t>(weight_base) << 22;
    value |= static_cast<__uint128_t>(bias_base) << 54;
    value |= static_cast<__uint128_t>(output_shift & 0x3Fu) << 86;
    value |= static_cast<__uint128_t>(relu_enable ? 1u : 0u) << 92;

    return {
        static_cast<std::uint32_t>(value),
        static_cast<std::uint32_t>(value >> 32),
        static_cast<std::uint32_t>(value >> 64)
    };
}

struct ScalarLayer {
    std::int8_t weight;
    std::int32_t bias;
    std::uint32_t shift;
    bool relu;
};

struct QuantCase {
    std::string name;
    std::int16_t input;
    std::vector<ScalarLayer> layers;
    std::int16_t expected;
};

struct DescriptorConfig {
    std::uint32_t index;
    std::uint32_t in_dim;
    std::uint32_t out_dim;
    std::uint32_t weight_base;
    std::uint32_t bias_base;
    std::uint32_t shift;
    bool relu;
};

struct ErrorCase {
    std::string name;
    std::uint32_t layer_count;
    std::vector<DescriptorConfig> descriptors;
    std::uint32_t expected_error;
};

struct ResultObservation {
    std::int32_t result;
    std::uint32_t meta;
    std::uint32_t result_status;
    std::uint32_t final_status;
    std::uint32_t result_count;
    double latency_us;
};

struct ErrorObservation {
    std::uint32_t error_status;
    std::uint32_t acknowledged_status;
    std::uint32_t observed_error;
};

class HalSession {
public:
    HalSession()
    {
        std::memcpy(uuid_, kExpectedUuidBytes, sizeof(uuid_));

        handle_ = xclOpen(kDeviceIndex, nullptr, XCL_QUIET);
        if (!handle_) {
            throw std::runtime_error("xclOpen(device index 2) failed");
        }

        const int detected_index = xclIPName2Index(handle_, kIpName);
        if (detected_index < 0) {
            std::ostringstream message;
            message << "xclIPName2Index failed for " << kIpName
                    << ": rc=" << detected_index;
            throw std::runtime_error(message.str());
        }

        ip_index_ = static_cast<unsigned int>(detected_index);

        std::cout << "HAL_DEVICE_INDEX=" << kDeviceIndex << "\n"
                  << "HAL_TARGET_BDF=" << kTargetBdf << "\n"
                  << "HAL_XCLBIN_UUID=" << uuid_to_string(uuid_) << "\n"
                  << "HAL_IP_NAME=" << kIpName << "\n"
                  << "HAL_IP_INDEX=" << ip_index_ << "\n";

        if (ip_index_ != kExpectedIpIndex) {
            std::ostringstream message;
            message << "unexpected IP index: expected "
                    << kExpectedIpIndex << ", got " << ip_index_;
            throw std::runtime_error(message.str());
        }

        const int context_rc =
            xclOpenContext(handle_, uuid_, ip_index_, false);
        if (context_rc != 0) {
            std::ostringstream message;
            message << "xclOpenContext(exclusive) failed: rc="
                    << context_rc;
            throw std::runtime_error(message.str());
        }

        context_open_ = true;
        std::cout << "HAL_EXCLUSIVE_CONTEXT_OPEN=1\n";
    }

    ~HalSession()
    {
        if (context_open_) {
            const int rc =
                xclCloseContext(handle_, uuid_, ip_index_);
            if (rc != 0) {
                std::cerr << "WARNING: xclCloseContext returned "
                          << rc << "\n";
            }
        }

        if (handle_) {
            xclClose(handle_);
        }
    }

    HalSession(const HalSession&) = delete;
    HalSession& operator=(const HalSession&) = delete;

    void write(std::uint32_t offset, std::uint32_t value)
    {
        const int rc =
            xclRegWrite(handle_, ip_index_, offset, value);
        if (rc != 0) {
            std::ostringstream message;
            message << "xclRegWrite failed: ipIndex=" << ip_index_
                    << " offset=" << hex32(offset)
                    << " value=" << hex32(value)
                    << " rc=" << rc;
            throw std::runtime_error(message.str());
        }
    }

    std::uint32_t read(std::uint32_t offset)
    {
        std::uint32_t value = 0;
        const int rc =
            xclRegRead(handle_, ip_index_, offset, &value);
        if (rc != 0) {
            std::ostringstream message;
            message << "xclRegRead failed: ipIndex=" << ip_index_
                    << " offset=" << hex32(offset)
                    << " rc=" << rc;
            throw std::runtime_error(message.str());
        }
        return value;
    }

private:
    xclDeviceHandle handle_ = nullptr;
    xuid_t uuid_ = {};
    unsigned int ip_index_ = 0;
    bool context_open_ = false;
};

void throw_on_error_status(std::uint32_t status, const char* context)
{
    if ((status & (STATUS_CORE_ERROR | STATUS_WRAPPER_ERROR)) == 0) {
        return;
    }

    const std::uint32_t core_error_code = (status >> 24) & 0xFu;
    const std::uint32_t wrapper_error_code = (status >> 28) & 0xFu;

    std::ostringstream message;
    message << context << ": kernel error status=" << hex32(status)
            << " core_error_code=" << core_error_code
            << " wrapper_error_code=" << wrapper_error_code;
    throw std::runtime_error(message.str());
}

template <typename Predicate>
std::uint32_t poll_clean_status(
    HalSession& session,
    Predicate predicate,
    const char* description,
    std::chrono::milliseconds timeout)
{
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    std::uint32_t status = 0;

    while (std::chrono::steady_clock::now() < deadline) {
        status = session.read(ADDR_CONTROL_STATUS);
        throw_on_error_status(status, description);

        if (predicate(status)) {
            return status;
        }

        std::this_thread::sleep_for(std::chrono::microseconds(25));
    }

    std::ostringstream message;
    message << "timeout while " << description
            << "; last status=" << hex32(status);
    throw std::runtime_error(message.str());
}

void wait_command_idle(HalSession& session, const char* description)
{
    poll_clean_status(
        session,
        [](std::uint32_t status) {
            return (status & STATUS_COMMAND_PENDING) == 0;
        },
        description,
        std::chrono::milliseconds(2000));
}

void write_descriptor(
    HalSession& session,
    std::uint32_t index,
    const DescriptorWords& descriptor)
{
    session.write(ADDR_DESC_INDEX, index);
    session.write(ADDR_DESC_WORD0, descriptor.word0);
    session.write(ADDR_DESC_WORD1, descriptor.word1);
    session.write(ADDR_DESC_WORD2, descriptor.word2);
    session.write(ADDR_CONTROL_STATUS, CMD_DESC_COMMIT);
    wait_command_idle(session, "waiting for descriptor commit");
}

void write_weight(
    HalSession& session,
    std::uint32_t address,
    std::int8_t value)
{
    session.write(ADDR_WEIGHT_ADDRESS, address);
    session.write(
        ADDR_WEIGHT_DATA,
        static_cast<std::uint32_t>(
            static_cast<std::uint8_t>(value)));
    session.write(ADDR_CONTROL_STATUS, CMD_WEIGHT_COMMIT);
    wait_command_idle(session, "waiting for weight commit");
}

void write_bias(
    HalSession& session,
    std::uint32_t address,
    std::int32_t value)
{
    if (value < -8388608 || value > 8388607) {
        throw std::runtime_error("bias exceeds signed 24-bit range");
    }

    const std::uint32_t packed =
        static_cast<std::uint32_t>(value) & 0x00FFFFFFu;

    session.write(ADDR_BIAS_ADDRESS, address);
    session.write(ADDR_BIAS_DATA, packed);
    session.write(ADDR_CONTROL_STATUS, CMD_BIAS_COMMIT);
    wait_command_idle(session, "waiting for bias commit");
}

void write_activation_lane0(
    HalSession& session,
    std::int16_t value)
{
    session.write(ADDR_ACT_BUFFER, 0);
    session.write(ADDR_ACT_CHUNK_INDEX, 0);
    session.write(ADDR_ACT_LANE_MASK, 0x00000001u);
    session.write(
        ADDR_ACT_DATA0,
        static_cast<std::uint32_t>(
            static_cast<std::uint16_t>(value)));
    session.write(ADDR_ACT_DATA1, 0);
    session.write(ADDR_ACT_DATA2, 0);
    session.write(ADDR_ACT_DATA3, 0);
    session.write(ADDR_ACT_DATA4, 0);
    session.write(ADDR_ACT_DATA5, 0);
    session.write(ADDR_ACT_DATA6, 0);
    session.write(ADDR_ACT_DATA7, 0);
    session.write(ADDR_CONTROL_STATUS, CMD_ACT_COMMIT);
    wait_command_idle(session, "waiting for activation commit");
}

std::int64_t round_shift_nearest_away(
    std::int64_t value,
    std::uint32_t shift)
{
    if (shift > ACC_WIDTH) {
        throw std::runtime_error("software shift exceeds ACC_WIDTH");
    }
    if (shift == 0u) {
        return value;
    }

    const bool negative = value < 0;
    const std::uint64_t magnitude =
        negative
        ? static_cast<std::uint64_t>(-(value + 1)) + 1u
        : static_cast<std::uint64_t>(value);
    const std::uint64_t rounding =
        static_cast<std::uint64_t>(1) << (shift - 1u);
    const std::uint64_t rounded =
        (magnitude + rounding) >> shift;

    return negative
        ? -static_cast<std::int64_t>(rounded)
        : static_cast<std::int64_t>(rounded);
}

std::int16_t quantize_reference(
    std::int64_t accumulator,
    std::uint32_t shift,
    bool relu)
{
    std::int64_t value =
        round_shift_nearest_away(accumulator, shift);

    if (value > std::numeric_limits<std::int16_t>::max()) {
        value = std::numeric_limits<std::int16_t>::max();
    }
    if (value < std::numeric_limits<std::int16_t>::min()) {
        value = std::numeric_limits<std::int16_t>::min();
    }

    if (relu && value < 0) {
        value = 0;
    }

    return static_cast<std::int16_t>(value);
}

std::int16_t software_reference(const QuantCase& test)
{
    std::int16_t activation = test.input;

    for (std::size_t index = 0;
         index < test.layers.size();
         ++index) {
        const ScalarLayer& layer = test.layers[index];
        const std::int64_t accumulator =
            static_cast<std::int64_t>(activation) *
            static_cast<std::int64_t>(layer.weight) +
            static_cast<std::int64_t>(layer.bias);

        activation = quantize_reference(
            accumulator, layer.shift, layer.relu);
    }

    return activation;
}

void prepare_clean_run(HalSession& session)
{
    const std::uint32_t status =
        session.read(ADDR_CONTROL_STATUS);
    throw_on_error_status(status, "pre-case status check");

    if ((status &
         (STATUS_BUSY |
          STATUS_COMMAND_PENDING |
          STATUS_RESULT_VALID)) != 0) {
        throw std::runtime_error(
            "kernel is not clean before case: status=" +
            hex32(status));
    }

    session.write(ADDR_CONTROL_STATUS, CMD_CLEAR_DONE);

    poll_clean_status(
        session,
        [](std::uint32_t current) {
            return (current & STATUS_DONE) == 0;
        },
        "clearing done before case",
        std::chrono::milliseconds(1000));
}

ResultObservation run_quant_case(
    HalSession& session,
    const QuantCase& test)
{
    if (test.layers.empty() ||
        test.layers.size() > MAX_LAYERS) {
        throw std::runtime_error(
            "invalid quantization-case layer count");
    }

    const std::int16_t reference =
        software_reference(test);
    if (reference != test.expected) {
        throw std::runtime_error(
            "embedded expected value is wrong for " +
            test.name);
    }

    prepare_clean_run(session);

    for (std::size_t layer_index = 0;
         layer_index < test.layers.size();
         ++layer_index) {
        const ScalarLayer& layer =
            test.layers[layer_index];
        const std::uint32_t address =
            static_cast<std::uint32_t>(layer_index);

        write_descriptor(
            session,
            address,
            pack_descriptor(
                1,
                1,
                address,
                address,
                layer.shift,
                layer.relu));
        write_weight(
            session, address, layer.weight);
        write_bias(
            session, address, layer.bias);
    }

    write_activation_lane0(session, test.input);

    session.write(
        ADDR_LAYER_COUNT,
        static_cast<std::uint32_t>(
            test.layers.size()));
    session.write(ADDR_INITIAL_BUFFER, 0);

    const auto start_time =
        std::chrono::steady_clock::now();

    session.write(ADDR_CONTROL_STATUS, CMD_START);
    wait_command_idle(
        session, "waiting for quantization start");

    const std::uint32_t result_status =
        poll_clean_status(
            session,
            [](std::uint32_t status) {
                return
                    (status & STATUS_RESULT_VALID) != 0;
            },
            "waiting for quantization result",
            std::chrono::milliseconds(5000));

    const auto result_time =
        std::chrono::steady_clock::now();

    const std::int32_t observed =
        static_cast<std::int32_t>(
            session.read(ADDR_RESULT_DATA));
    const std::uint32_t result_index =
        session.read(ADDR_RESULT_INDEX) & 0x3FFu;
    const std::uint32_t meta =
        session.read(ADDR_RESULT_META);
    const std::uint32_t expected_tag =
        static_cast<std::uint32_t>(
            test.layers.size() - 1u);
    const std::uint32_t observed_tag =
        (meta >> 8) & 0xFFu;
    const bool expected_final_buffer =
        (test.layers.size() & 1u) != 0u;
    const bool observed_final_buffer =
        (result_status & STATUS_FINAL_BUFFER) != 0u;

    session.write(
        ADDR_CONTROL_STATUS, CMD_RESULT_POP);

    const std::uint32_t final_status =
        poll_clean_status(
            session,
            [](std::uint32_t status) {
                return
                    (status & STATUS_DONE) != 0 &&
                    (status & STATUS_RESULT_VALID) == 0 &&
                    (status & STATUS_BUSY) == 0;
            },
            "waiting for quantization completion",
            std::chrono::milliseconds(5000));

    const std::uint32_t result_count =
        session.read(ADDR_RESULT_COUNT);

    if (observed !=
        static_cast<std::int32_t>(test.expected)) {
        throw std::runtime_error(
            "result mismatch for " + test.name +
            ": expected " +
            std::to_string(test.expected) +
            ", got " + std::to_string(observed));
    }
    if (result_index != 0u) {
        throw std::runtime_error(
            "result index mismatch for " + test.name);
    }
    if ((meta & 0x3u) != 0x3u) {
        throw std::runtime_error(
            "valid/last metadata mismatch for " +
            test.name);
    }
    if (observed_tag != expected_tag) {
        throw std::runtime_error(
            "layer tag mismatch for " + test.name);
    }
    if (observed_final_buffer !=
        expected_final_buffer) {
        throw std::runtime_error(
            "final-buffer mismatch for " +
            test.name);
    }
    if (result_count != 1u) {
        throw std::runtime_error(
            "result count mismatch for " +
            test.name);
    }

    ResultObservation result;
    result.result = observed;
    result.meta = meta;
    result.result_status = result_status;
    result.final_status = final_status;
    result.result_count = result_count;
    result.latency_us =
        std::chrono::duration<double, std::micro>(
            result_time - start_time).count();
    return result;
}

std::uint32_t poll_expected_error(
    HalSession& session,
    const ErrorCase& test)
{
    const auto deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(2000);
    std::uint32_t status = 0;

    while (std::chrono::steady_clock::now() < deadline) {
        status = session.read(ADDR_CONTROL_STATUS);

        if ((status &
             (STATUS_CORE_ERROR |
              STATUS_WRAPPER_ERROR)) != 0) {
            return status;
        }

        std::this_thread::sleep_for(
            std::chrono::microseconds(25));
    }

    throw std::runtime_error(
        "timeout waiting for expected error in " +
        test.name + "; last status=" +
        hex32(status));
}

ErrorObservation run_error_case(
    HalSession& session,
    const ErrorCase& test)
{
    prepare_clean_run(session);

    for (std::size_t index = 0;
         index < test.descriptors.size();
         ++index) {
        const DescriptorConfig& descriptor =
            test.descriptors[index];

        write_descriptor(
            session,
            descriptor.index,
            pack_descriptor(
                descriptor.in_dim,
                descriptor.out_dim,
                descriptor.weight_base,
                descriptor.bias_base,
                descriptor.shift,
                descriptor.relu));
    }

    session.write(
        ADDR_LAYER_COUNT, test.layer_count);
    session.write(ADDR_INITIAL_BUFFER, 0);
    session.write(ADDR_CONTROL_STATUS, CMD_START);

    const std::uint32_t error_status =
        poll_expected_error(session, test);
    const std::uint32_t core_error =
        (error_status >> 24) & 0xFu;
    const std::uint32_t wrapper_error =
        (error_status >> 28) & 0xFu;

    if (core_error != test.expected_error ||
        wrapper_error != 0u) {
        throw std::runtime_error(
            "wrong error for " + test.name +
            ": expected core=" +
            std::to_string(test.expected_error) +
            ", observed core=" +
            std::to_string(core_error) +
            ", wrapper=" +
            std::to_string(wrapper_error));
    }
    if ((error_status & STATUS_RESULT_VALID) != 0) {
        throw std::runtime_error(
            "unexpected result-valid during " +
            test.name);
    }

    session.write(
        ADDR_CONTROL_STATUS, CMD_ERROR_ACK);

    const auto deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(2000);
    std::uint32_t acknowledged_status =
        error_status;

    while (std::chrono::steady_clock::now() < deadline) {
        acknowledged_status =
            session.read(ADDR_CONTROL_STATUS);

        if ((acknowledged_status &
             (STATUS_CORE_ERROR |
              STATUS_WRAPPER_ERROR |
              STATUS_BUSY |
              STATUS_COMMAND_PENDING |
              STATUS_RESULT_VALID)) == 0) {
            break;
        }

        std::this_thread::sleep_for(
            std::chrono::microseconds(25));
    }

    if ((acknowledged_status &
         (STATUS_CORE_ERROR |
          STATUS_WRAPPER_ERROR |
          STATUS_BUSY |
          STATUS_COMMAND_PENDING |
          STATUS_RESULT_VALID)) != 0) {
        throw std::runtime_error(
            "ERROR_ACK did not restore IDLE after " +
            test.name + "; status=" +
            hex32(acknowledged_status));
    }

    ErrorObservation observation;
    observation.error_status = error_status;
    observation.acknowledged_status =
        acknowledged_status;
    observation.observed_error = core_error;
    return observation;
}

QuantCase recovery_probe(const std::string& suffix)
{
    QuantCase test;
    test.name = "recovery_probe_" + suffix;
    test.input = 3;
    test.layers.push_back({2, 1, 0, false});
    test.layers.push_back({3, -2, 0, false});
    test.expected = 19;
    return test;
}

std::vector<QuantCase> quant_cases()
{
    std::vector<QuantCase> cases;

    cases.push_back(
        {"shift1_positive_tie", 0,
         {{0, 1, 1, false}}, 1});
    cases.push_back(
        {"shift1_positive_three", 0,
         {{0, 3, 1, false}}, 2});
    cases.push_back(
        {"shift1_negative_tie", 0,
         {{0, -1, 1, false}}, -1});
    cases.push_back(
        {"shift1_negative_three", 0,
         {{0, -3, 1, false}}, -2});

    cases.push_back(
        {"shift2_positive_below_half", 0,
         {{0, 1, 2, false}}, 0});
    cases.push_back(
        {"shift2_positive_tie", 0,
         {{0, 2, 2, false}}, 1});
    cases.push_back(
        {"shift2_negative_below_half", 0,
         {{0, -1, 2, false}}, 0});
    cases.push_back(
        {"shift2_negative_tie", 0,
         {{0, -2, 2, false}}, -1});

    cases.push_back(
        {"shift4_positive_tie", 0,
         {{0, 24, 4, false}}, 2});
    cases.push_back(
        {"shift4_negative_tie", 0,
         {{0, -24, 4, false}}, -2});

    cases.push_back(
        {"shift16_positive_tie", 0,
         {{0, 32768, 16, false}}, 1});
    cases.push_back(
        {"shift16_negative_tie", 0,
         {{0, -32768, 16, false}}, -1});

    cases.push_back(
        {"shift48_valid_max_bias", 0,
         {{0, 8388607, 48, false}}, 0});

    cases.push_back(
        {"positive_saturation", 0,
         {{0, 8388607, 0, false}}, 32767});
    cases.push_back(
        {"negative_saturation", 0,
         {{0, -8388608, 0, false}}, -32768});
    cases.push_back(
        {"relu_after_negative_saturation", 0,
         {{0, -8388608, 0, true}}, 0});

    cases.push_back(
        {"intermediate_positive_rounding", 0,
         {{0, 3, 1, false},
          {5, 0, 0, false}}, 10});
    cases.push_back(
        {"intermediate_negative_rounding", 0,
         {{0, -3, 1, false},
          {4, 0, 0, false}}, -8});

    cases.push_back(
        {"intermediate_positive_saturation", 0,
         {{0, 40000, 0, false},
          {1, -32767, 0, false}}, 0});
    cases.push_back(
        {"intermediate_negative_saturation", 0,
         {{0, -40000, 0, false},
          {1, 32768, 0, false}}, 0});

    return cases;
}

std::vector<ErrorCase> error_cases()
{
    std::vector<ErrorCase> cases;

    cases.push_back({
        "bad_layer_count_zero",
        0,
        {},
        ERROR_BAD_LAYER_COUNT
    });

    cases.push_back({
        "bad_layer_count_five",
        5,
        {},
        ERROR_BAD_LAYER_COUNT
    });

    cases.push_back({
        "bad_dimension_zero_input",
        1,
        {{0, 0, 1, 0, 0, 0, false}},
        ERROR_BAD_DIMENSION
    });

    cases.push_back({
        "bad_dimension_output_1025",
        1,
        {{0, 1, 1025, 0, 0, 0, false}},
        ERROR_BAD_DIMENSION
    });

    cases.push_back({
        "dimension_mismatch",
        2,
        {
            {0, 1, 2, 0, 0, 0, false},
            {1, 3, 1, 2, 2, 0, false}
        },
        ERROR_DIMENSION_MISMATCH
    });

    cases.push_back({
        "weight_range_overflow",
        1,
        {
            {0, 2, 2,
             MAX_WEIGHT_VALUES - 2u,
             0, 0, false}
        },
        ERROR_WEIGHT_RANGE
    });

    cases.push_back({
        "bias_range_overflow",
        1,
        {
            {0, 1, 2,
             0,
             MAX_BIAS_VALUES - 1u,
             0, false}
        },
        ERROR_BIAS_RANGE
    });

    cases.push_back({
        "bad_shift_49",
        1,
        {{0, 1, 1, 0, 0, 49, false}},
        ERROR_BAD_SHIFT
    });

    return cases;
}

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc != 2) {
            std::cerr
                << "Usage: " << argv[0]
                << " <results.csv>\n";
            return EXIT_FAILURE;
        }

        const std::string csv_path = argv[1];

        std::cout
            << "Stage 2K-C F37X quantization and validation regression\n"
            << "Access path: xclOpenContext + xclRegRead/xclRegWrite\n"
            << "POSITIVE_CASES=20\n"
            << "ERROR_CASES=8\n"
            << "RECOVERY_PROBES=8\n"
            << "MISSING_DESCRIPTOR_BOUNDARY="
            << "not_testable_without_clearing_persistent_descriptor_table\n"
            << "CSV=" << csv_path << "\n";

        HalSession session;

        const std::uint32_t version =
            session.read(ADDR_VERSION);
        const std::uint32_t initial_status =
            session.read(ADDR_CONTROL_STATUS);

        std::cout << "VERSION=" << hex32(version) << "\n"
                  << "INITIAL_STATUS="
                  << hex32(initial_status) << "\n";

        if (version != EXPECTED_VERSION) {
            throw std::runtime_error(
                "wrapper version mismatch: expected " +
                hex32(EXPECTED_VERSION) + ", got " +
                hex32(version));
        }

        throw_on_error_status(
            initial_status, "initial status check");

        std::ofstream csv(csv_path.c_str());
        if (!csv) {
            throw std::runtime_error(
                "cannot open CSV output: " + csv_path);
        }

        csv
            << "sequence,case_name,category,kind,layer_count,"
            << "input,shift0,relu0,expected_result,observed_result,"
            << "expected_error,observed_error,result_meta,raw_status,"
            << "status_after_ack,result_count,latency_us,status\n";

        const std::vector<QuantCase> positives =
            quant_cases();
        const std::vector<ErrorCase> errors =
            error_cases();

        if (positives.size() != 20u ||
            errors.size() != 8u) {
            throw std::runtime_error(
                "internal Stage 2K-C case-count error");
        }

        unsigned int sequence = 0;
        unsigned int positive_passes = 0;
        unsigned int error_passes = 0;
        unsigned int recovery_passes = 0;

        for (std::size_t index = 0;
             index < positives.size();
             ++index) {
            const QuantCase& test = positives[index];
            const ResultObservation result =
                run_quant_case(session, test);

            ++sequence;
            ++positive_passes;

            csv
                << sequence << ","
                << test.name << ",quantization,result,"
                << test.layers.size() << ","
                << test.input << ","
                << test.layers[0].shift << ","
                << (test.layers[0].relu ? 1 : 0) << ","
                << test.expected << ","
                << result.result << ","
                << ",,"
                << hex32(result.meta) << ","
                << hex32(result.result_status) << ","
                << hex32(result.final_status) << ","
                << result.result_count << ","
                << std::fixed << std::setprecision(3)
                << result.latency_us << ",PASS\n";

            std::cout
                << "QUANT_CASE_PASS"
                << " sequence=" << sequence
                << " name=" << test.name
                << " layers=" << test.layers.size()
                << " result=" << result.result
                << " latency_us=" << std::fixed
                << std::setprecision(3)
                << result.latency_us
                << "\n";
        }

        for (std::size_t index = 0;
             index < errors.size();
             ++index) {
            const ErrorCase& test = errors[index];
            const ErrorObservation error =
                run_error_case(session, test);

            ++sequence;
            ++error_passes;

            csv
                << sequence << ","
                << test.name << ",validation,error,"
                << test.layer_count << ","
                << ",,,,"
                << ","
                << test.expected_error << ","
                << error.observed_error << ","
                << ","
                << hex32(error.error_status) << ","
                << hex32(error.acknowledged_status) << ","
                << ",,PASS\n";

            std::cout
                << "ERROR_CASE_PASS"
                << " sequence=" << sequence
                << " name=" << test.name
                << " expected_error="
                << test.expected_error
                << " error_name="
                << error_name(test.expected_error)
                << " raw_status="
                << hex32(error.error_status)
                << " acknowledged_status="
                << hex32(error.acknowledged_status)
                << "\n";

            const QuantCase probe =
                recovery_probe(test.name);
            const ResultObservation probe_result =
                run_quant_case(session, probe);

            ++sequence;
            ++recovery_passes;

            csv
                << sequence << ","
                << probe.name << ",recovery,result,"
                << probe.layers.size() << ","
                << probe.input << ","
                << probe.layers[0].shift << ","
                << (probe.layers[0].relu ? 1 : 0) << ","
                << probe.expected << ","
                << probe_result.result << ","
                << ",,"
                << hex32(probe_result.meta) << ","
                << hex32(probe_result.result_status) << ","
                << hex32(probe_result.final_status) << ","
                << probe_result.result_count << ","
                << std::fixed << std::setprecision(3)
                << probe_result.latency_us << ",PASS\n";

            std::cout
                << "RECOVERY_PROBE_PASS"
                << " sequence=" << sequence
                << " after=" << test.name
                << " result=" << probe_result.result
                << "\n";
        }

        csv.flush();
        if (!csv) {
            throw std::runtime_error(
                "failed while writing Stage 2K-C CSV");
        }

        const std::uint32_t final_status =
            session.read(ADDR_CONTROL_STATUS);
        throw_on_error_status(
            final_status, "final status check");

        if ((final_status &
             (STATUS_BUSY |
              STATUS_RESULT_VALID |
              STATUS_COMMAND_PENDING)) != 0) {
            throw std::runtime_error(
                "kernel is not clean after Stage 2K-C: " +
                hex32(final_status));
        }

        std::cout
            << "POSITIVE_CASES=" << positive_passes << "\n"
            << "ERROR_CASES=" << error_passes << "\n"
            << "RECOVERY_PROBES=" << recovery_passes << "\n"
            << "TOTAL_RECORDS=" << sequence << "\n"
            << "FINAL_STATUS=" << hex32(final_status) << "\n"
            << "STAGE2K_C_QUANT_ERROR_REGRESSION_PASS"
            << " positive=" << positive_passes
            << " errors=" << error_passes
            << " recovery=" << recovery_passes
            << " records=" << sequence
            << "\n";

        return EXIT_SUCCESS;
    }
    catch (const std::exception& error) {
        std::cerr
            << "STAGE2K_C_QUANT_ERROR_REGRESSION_FAILED: "
            << error.what() << "\n";
        return EXIT_FAILURE;
    }
}
