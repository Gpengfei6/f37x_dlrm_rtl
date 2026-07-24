#include <xrt.h>
#include <experimental/xrt-next.h>

#include <algorithm>
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
constexpr std::uint32_t STATUS_RESULT_LAST = 1u << 3;
constexpr std::uint32_t STATUS_CORE_ERROR = 1u << 4;
constexpr std::uint32_t STATUS_WRAPPER_ERROR = 1u << 5;
constexpr std::uint32_t STATUS_FINAL_BUFFER = 1u << 6;
constexpr std::uint32_t STATUS_COMMAND_PENDING = 1u << 7;

constexpr std::uint32_t EXPECTED_VERSION = 0x00024701;
constexpr std::size_t NUM_PE = 16;
constexpr std::size_t MAX_LAYERS = 4;

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

struct MatrixLayer {
    std::vector<std::vector<std::int8_t> > weights;
    std::vector<std::int32_t> biases;
    bool relu;
};

struct MatrixCase {
    std::string name;
    std::vector<std::int16_t> input;
    std::vector<MatrixLayer> layers;
    std::uint32_t initial_buffer;
    std::vector<std::int16_t> expected;
};

struct OutputObservation {
    std::uint32_t index;
    std::int32_t value;
    std::uint32_t meta;
    std::uint32_t status;
    std::uint32_t result_count_after_pop;
};

struct CaseResult {
    std::vector<OutputObservation> outputs;
    std::uint32_t final_status;
    double first_result_latency_us;
    double final_result_latency_us;
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
std::uint32_t poll_status(
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
    poll_status(
        session,
        [](std::uint32_t status) {
            return (status & STATUS_COMMAND_PENDING) == 0;
        },
        description,
        std::chrono::milliseconds(2000));
}

void wait_result_count(
    HalSession& session,
    std::uint32_t expected_count)
{
    const auto deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(2000);
    std::uint32_t count = 0;

    while (std::chrono::steady_clock::now() < deadline) {
        const std::uint32_t status =
            session.read(ADDR_CONTROL_STATUS);
        throw_on_error_status(
            status, "waiting for result-count increment");

        count = session.read(ADDR_RESULT_COUNT);
        if (count == expected_count) {
            return;
        }

        if (count > expected_count) {
            throw std::runtime_error(
                "result count advanced unexpectedly: expected " +
                std::to_string(expected_count) +
                ", got " + std::to_string(count));
        }

        std::this_thread::sleep_for(
            std::chrono::microseconds(25));
    }

    throw std::runtime_error(
        "timeout waiting for result count " +
        std::to_string(expected_count) +
        "; last count=" + std::to_string(count));
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

void write_activation_vector(
    HalSession& session,
    const std::vector<std::int16_t>& values,
    std::uint32_t buffer_select)
{
    if (buffer_select > 1u) {
        throw std::runtime_error("activation buffer select must be 0 or 1");
    }

    const std::size_t chunk_count =
        (values.size() + NUM_PE - 1u) / NUM_PE;

    for (std::size_t chunk = 0; chunk < chunk_count; ++chunk) {
        std::uint32_t registers[8] = {};
        std::uint32_t lane_mask = 0;

        for (std::size_t lane = 0; lane < NUM_PE; ++lane) {
            const std::size_t value_index =
                chunk * NUM_PE + lane;
            if (value_index >= values.size()) {
                continue;
            }

            lane_mask |= (1u << lane);
            const std::uint32_t packed_value =
                static_cast<std::uint32_t>(
                    static_cast<std::uint16_t>(
                        values[value_index]));
            const std::size_t register_index = lane / 2u;

            if ((lane & 1u) == 0u) {
                registers[register_index] |= packed_value;
            }
            else {
                registers[register_index] |=
                    packed_value << 16;
            }
        }

        session.write(ADDR_ACT_BUFFER, buffer_select);
        session.write(
            ADDR_ACT_CHUNK_INDEX,
            static_cast<std::uint32_t>(chunk));
        session.write(ADDR_ACT_LANE_MASK, lane_mask);
        session.write(ADDR_ACT_DATA0, registers[0]);
        session.write(ADDR_ACT_DATA1, registers[1]);
        session.write(ADDR_ACT_DATA2, registers[2]);
        session.write(ADDR_ACT_DATA3, registers[3]);
        session.write(ADDR_ACT_DATA4, registers[4]);
        session.write(ADDR_ACT_DATA5, registers[5]);
        session.write(ADDR_ACT_DATA6, registers[6]);
        session.write(ADDR_ACT_DATA7, registers[7]);
        session.write(ADDR_CONTROL_STATUS, CMD_ACT_COMMIT);
        wait_command_idle(
            session, "waiting for activation-chunk commit");
    }
}

std::int16_t quantize_shift_zero(
    std::int64_t accumulator,
    bool relu)
{
    if (relu && accumulator < 0) {
        accumulator = 0;
    }

    if (accumulator >
        static_cast<std::int64_t>(
            std::numeric_limits<std::int16_t>::max())) {
        accumulator =
            std::numeric_limits<std::int16_t>::max();
    }
    if (accumulator <
        static_cast<std::int64_t>(
            std::numeric_limits<std::int16_t>::min())) {
        accumulator =
            std::numeric_limits<std::int16_t>::min();
    }

    return static_cast<std::int16_t>(accumulator);
}

std::vector<std::int16_t> software_reference(
    const MatrixCase& test)
{
    std::vector<std::int16_t> activations = test.input;

    for (std::size_t layer_index = 0;
         layer_index < test.layers.size();
         ++layer_index) {
        const MatrixLayer& layer =
            test.layers[layer_index];

        if (layer.weights.empty()) {
            throw std::runtime_error(
                "layer has zero outputs in case " + test.name);
        }
        if (layer.biases.size() != layer.weights.size()) {
            throw std::runtime_error(
                "bias/output mismatch in case " + test.name);
        }

        std::vector<std::int16_t> outputs;
        outputs.reserve(layer.weights.size());

        for (std::size_t output_index = 0;
             output_index < layer.weights.size();
             ++output_index) {
            const std::vector<std::int8_t>& row =
                layer.weights[output_index];

            if (row.size() != activations.size()) {
                throw std::runtime_error(
                    "weight-row/input mismatch in case " +
                    test.name);
            }

            std::int64_t accumulator =
                layer.biases[output_index];

            for (std::size_t input_index = 0;
                 input_index < activations.size();
                 ++input_index) {
                accumulator +=
                    static_cast<std::int64_t>(
                        activations[input_index]) *
                    static_cast<std::int64_t>(
                        row[input_index]);
            }

            outputs.push_back(
                quantize_shift_zero(
                    accumulator, layer.relu));
        }

        activations = outputs;
    }

    return activations;
}

void validate_case(const MatrixCase& test)
{
    if (test.layers.empty() ||
        test.layers.size() > MAX_LAYERS) {
        throw std::runtime_error(
            "case layer count is outside 1..4: " +
            test.name);
    }
    if (test.input.empty()) {
        throw std::runtime_error(
            "case input vector is empty: " + test.name);
    }
    if (test.initial_buffer > 1u) {
        throw std::runtime_error(
            "invalid initial buffer in case: " + test.name);
    }

    std::size_t expected_in_dim = test.input.size();

    for (std::size_t layer_index = 0;
         layer_index < test.layers.size();
         ++layer_index) {
        const MatrixLayer& layer =
            test.layers[layer_index];

        if (layer.weights.empty()) {
            throw std::runtime_error(
                "zero output dimension in case " +
                test.name);
        }
        if (layer.biases.size() != layer.weights.size()) {
            throw std::runtime_error(
                "bias count mismatch in case " +
                test.name);
        }

        for (std::size_t output_index = 0;
             output_index < layer.weights.size();
             ++output_index) {
            if (layer.weights[output_index].size() !=
                expected_in_dim) {
                throw std::runtime_error(
                    "dimension mismatch in case " +
                    test.name);
            }
        }

        expected_in_dim = layer.weights.size();
    }

    const std::vector<std::int16_t> reference =
        software_reference(test);
    if (reference != test.expected) {
        throw std::runtime_error(
            "embedded expected vector does not match "
            "software reference for case " + test.name);
    }
}

void prepare_clean_run(HalSession& session)
{
    const std::uint32_t status =
        session.read(ADDR_CONTROL_STATUS);
    throw_on_error_status(status, "pre-case status check");

    if ((status &
         (STATUS_BUSY | STATUS_COMMAND_PENDING |
          STATUS_RESULT_VALID)) != 0) {
        throw std::runtime_error(
            "kernel is not clean before case: status=" +
            hex32(status));
    }

    session.write(ADDR_CONTROL_STATUS, CMD_CLEAR_DONE);

    poll_status(
        session,
        [](std::uint32_t current) {
            return (current & STATUS_DONE) == 0;
        },
        "clearing done before matrix case",
        std::chrono::milliseconds(1000));
}

CaseResult run_matrix_case(
    HalSession& session,
    const MatrixCase& test)
{
    validate_case(test);
    prepare_clean_run(session);

    std::uint32_t weight_base = 0;
    std::uint32_t bias_base = 0;

    for (std::size_t layer_index = 0;
         layer_index < test.layers.size();
         ++layer_index) {
        const MatrixLayer& layer =
            test.layers[layer_index];
        const std::uint32_t in_dim =
            static_cast<std::uint32_t>(
                layer.weights[0].size());
        const std::uint32_t out_dim =
            static_cast<std::uint32_t>(
                layer.weights.size());

        write_descriptor(
            session,
            static_cast<std::uint32_t>(layer_index),
            pack_descriptor(
                in_dim,
                out_dim,
                weight_base,
                bias_base,
                0,
                layer.relu));

        for (std::size_t output_index = 0;
             output_index < layer.weights.size();
             ++output_index) {
            for (std::size_t input_index = 0;
                 input_index <
                    layer.weights[output_index].size();
                 ++input_index) {
                const std::uint32_t address =
                    weight_base +
                    static_cast<std::uint32_t>(
                        output_index * in_dim +
                        input_index);
                write_weight(
                    session,
                    address,
                    layer.weights[output_index]
                                 [input_index]);
            }

            write_bias(
                session,
                bias_base +
                    static_cast<std::uint32_t>(
                        output_index),
                layer.biases[output_index]);
        }

        weight_base += in_dim * out_dim;
        bias_base += out_dim;
    }

    write_activation_vector(
        session, test.input, test.initial_buffer);

    session.write(
        ADDR_LAYER_COUNT,
        static_cast<std::uint32_t>(
            test.layers.size()));
    session.write(
        ADDR_INITIAL_BUFFER,
        test.initial_buffer);

    const auto start_time =
        std::chrono::steady_clock::now();

    session.write(ADDR_CONTROL_STATUS, CMD_START);
    wait_command_idle(
        session, "waiting for matrix start acceptance");

    CaseResult case_result;
    case_result.first_result_latency_us = 0.0;
    case_result.final_result_latency_us = 0.0;

    const std::uint32_t final_out_dim =
        static_cast<std::uint32_t>(
            test.expected.size());
    const std::uint32_t expected_tag =
        static_cast<std::uint32_t>(
            test.layers.size() - 1u);
    const bool expected_final_buffer =
        ((test.initial_buffer ^
          static_cast<std::uint32_t>(
              test.layers.size() & 1u)) != 0u);

    for (std::uint32_t expected_index = 0;
         expected_index < final_out_dim;
         ++expected_index) {
        const std::uint32_t status = poll_status(
            session,
            [](std::uint32_t current) {
                return (current & STATUS_RESULT_VALID) != 0;
            },
            "waiting for matrix output",
            std::chrono::milliseconds(5000));

        const auto result_time =
            std::chrono::steady_clock::now();
        const double latency_us =
            std::chrono::duration<double, std::micro>(
                result_time - start_time).count();

        if (expected_index == 0u) {
            case_result.first_result_latency_us =
                latency_us;
        }
        case_result.final_result_latency_us =
            latency_us;

        const std::int32_t observed =
            static_cast<std::int32_t>(
                session.read(ADDR_RESULT_DATA));
        const std::uint32_t observed_index =
            session.read(ADDR_RESULT_INDEX) & 0x3FFu;
        const std::uint32_t meta =
            session.read(ADDR_RESULT_META);
        const std::uint32_t tag =
            (meta >> 8) & 0xFFu;
        const bool observed_last =
            (meta & 0x2u) != 0u;
        const bool expected_last =
            (expected_index + 1u == final_out_dim);
        const bool observed_final_buffer =
            (status & STATUS_FINAL_BUFFER) != 0u;

        /*
         * Pop before throwing numerical assertions.  This prevents a failed
         * comparison from leaving the final-output FIFO blocked.
         */
        session.write(ADDR_CONTROL_STATUS, CMD_RESULT_POP);
        wait_result_count(session, expected_index + 1u);

        if (observed_index != expected_index) {
            throw std::runtime_error(
                "result index mismatch in " + test.name +
                ": expected " +
                std::to_string(expected_index) +
                ", got " +
                std::to_string(observed_index));
        }
        if (observed !=
            static_cast<std::int32_t>(
                test.expected[expected_index])) {
            throw std::runtime_error(
                "result value mismatch in " + test.name +
                " output " +
                std::to_string(expected_index) +
                ": expected " +
                std::to_string(
                    test.expected[expected_index]) +
                ", got " +
                std::to_string(observed));
        }
        if ((meta & 0x1u) == 0u) {
            throw std::runtime_error(
                "result valid bit missing in " +
                test.name);
        }
        if (observed_last != expected_last) {
            throw std::runtime_error(
                "result last mismatch in " + test.name +
                " output " +
                std::to_string(expected_index));
        }
        if (tag != expected_tag) {
            throw std::runtime_error(
                "result tag mismatch in " + test.name +
                ": expected " +
                std::to_string(expected_tag) +
                ", got " + std::to_string(tag));
        }
        if (observed_final_buffer !=
            expected_final_buffer) {
            throw std::runtime_error(
                "final-buffer mismatch in " +
                test.name);
        }

        OutputObservation observation;
        observation.index = observed_index;
        observation.value = observed;
        observation.meta = meta;
        observation.status = status;
        observation.result_count_after_pop =
            expected_index + 1u;
        case_result.outputs.push_back(observation);
    }

    case_result.final_status = poll_status(
        session,
        [](std::uint32_t status) {
            return (status & STATUS_DONE) != 0 &&
                   (status & STATUS_RESULT_VALID) == 0 &&
                   (status & STATUS_BUSY) == 0;
        },
        "waiting for matrix case completion",
        std::chrono::milliseconds(5000));

    const std::uint32_t final_count =
        session.read(ADDR_RESULT_COUNT);
    if (final_count != final_out_dim) {
        throw std::runtime_error(
            "final output count mismatch in " +
            test.name + ": expected " +
            std::to_string(final_out_dim) +
            ", got " + std::to_string(final_count));
    }

    const bool final_status_buffer =
        (case_result.final_status &
         STATUS_FINAL_BUFFER) != 0u;
    if (final_status_buffer != expected_final_buffer) {
        throw std::runtime_error(
            "final status buffer mismatch in " +
            test.name);
    }

    return case_result;
}

MatrixLayer make_layer(
    const std::vector<std::vector<int> >& weights,
    const std::vector<int>& biases,
    bool relu)
{
    MatrixLayer layer;
    layer.relu = relu;

    for (std::size_t row_index = 0;
         row_index < weights.size();
         ++row_index) {
        std::vector<std::int8_t> row;
        for (std::size_t column_index = 0;
             column_index < weights[row_index].size();
             ++column_index) {
            const int value =
                weights[row_index][column_index];
            if (value < -128 || value > 127) {
                throw std::runtime_error(
                    "test weight exceeds signed 8-bit range");
            }
            row.push_back(
                static_cast<std::int8_t>(value));
        }
        layer.weights.push_back(row);
    }

    for (std::size_t index = 0;
         index < biases.size();
         ++index) {
        layer.biases.push_back(biases[index]);
    }

    return layer;
}

std::vector<std::int16_t> make_i16(
    const std::vector<int>& values)
{
    std::vector<std::int16_t> output;
    for (std::size_t index = 0;
         index < values.size();
         ++index) {
        if (values[index] < -32768 ||
            values[index] > 32767) {
            throw std::runtime_error(
                "test activation exceeds signed 16-bit range");
        }
        output.push_back(
            static_cast<std::int16_t>(values[index]));
    }
    return output;
}

std::vector<MatrixCase> directed_cases()
{
    std::vector<MatrixCase> cases;

    cases.push_back({
        "single_3x2",
        make_i16({1, 2, 3}),
        {
            make_layer(
                {{1, 2, 3}, {-1, 0, 2}},
                {1, -2},
                false)
        },
        0,
        make_i16({15, 3})
    });

    cases.push_back({
        "single_5x3_signed",
        make_i16({-2, 1, 3, 0, 4}),
        {
            make_layer(
                {
                    {2, -1, 0, 3, 1},
                    {-2, 2, 1, -1, 0},
                    {1, 1, 1, 1, 1}
                },
                {-1, 2, 0},
                false)
        },
        0,
        make_i16({-2, 11, 6})
    });

    cases.push_back({
        "two_layer_3x2x2",
        make_i16({2, -1, 3}),
        {
            make_layer(
                {{1, 2, -1}, {0, -2, 3}},
                {1, -1},
                false),
            make_layer(
                {{2, 1}, {-1, 3}},
                {0, 2},
                false)
        },
        0,
        make_i16({6, 34})
    });

    cases.push_back({
        "two_layer_relu_4x3x2",
        make_i16({-3, 2, 1, 4}),
        {
            make_layer(
                {
                    {1, 1, -2, 0},
                    {-1, 2, 1, -1},
                    {2, -1, 0, 1}
                },
                {0, 1, -2},
                true),
            make_layer(
                {{2, -1, 1}, {1, 3, -2}},
                {1, -1},
                false)
        },
        0,
        make_i16({-4, 14})
    });

    std::vector<int> input16;
    for (int value = -8; value < 8; ++value) {
        input16.push_back(value);
    }

    std::vector<int> alternating16;
    std::vector<int> modulo16;
    std::vector<int> pattern16;
    for (int index = 0; index < 16; ++index) {
        alternating16.push_back(
            (index % 2 == 0) ? 1 : -1);
        modulo16.push_back((index % 3) - 1);
    }
    const int pattern_values[4] = {0, 1, -1, 2};
    for (int index = 0; index < 16; ++index) {
        pattern16.push_back(
            pattern_values[index % 4]);
    }

    cases.push_back({
        "single_16x4_full_chunk",
        make_i16(input16),
        {
            make_layer(
                {
                    std::vector<int>(16, 1),
                    alternating16,
                    modulo16,
                    pattern16
                },
                {0, 3, -2, 1},
                false)
        },
        0,
        make_i16({-8, -5, 1, 5})
    });

    std::vector<int> input17;
    std::vector<int> ones17(17, 1);
    std::vector<int> split17;
    std::vector<int> patterned17;

    for (int index = 0; index < 17; ++index) {
        input17.push_back(index + 1);
        split17.push_back(index < 8 ? 1 : -1);
        patterned17.push_back(
            ((index * 2) % 5) - 2);
    }

    cases.push_back({
        "single_17x3_two_chunks",
        make_i16(input17),
        {
            make_layer(
                {ones17, split17, patterned17},
                {-10, 5, 7},
                false)
        },
        0,
        make_i16({143, -76, -10})
    });

    cases.push_back({
        "single_3x2_initial_buffer_one",
        make_i16({3, -2, 5}),
        {
            make_layer(
                {{2, 0, -1}, {-1, 3, 1}},
                {1, -2},
                false)
        },
        1,
        make_i16({2, -6})
    });

    return cases;
}

MatrixCase stability_case()
{
    std::vector<int> input17;
    std::vector<int> ones17(17, 1);
    std::vector<int> split17;
    std::vector<int> patterned17;

    for (int index = 0; index < 17; ++index) {
        input17.push_back(index + 1);
        split17.push_back(index < 8 ? 1 : -1);
        patterned17.push_back(
            ((index * 2) % 5) - 2);
    }

    MatrixCase test = {
        "stability_17x3_two_chunks",
        make_i16(input17),
        {
            make_layer(
                {ones17, split17, patterned17},
                {-10, 5, 7},
                false)
        },
        0,
        make_i16({143, -76, -10})
    };

    return test;
}

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc < 2 || argc > 3) {
            std::cerr
                << "Usage: " << argv[0]
                << " <results.csv> [stability_repetitions]\n";
            return EXIT_FAILURE;
        }

        const std::string csv_path = argv[1];
        unsigned int stability_repetitions = 50;

        if (argc == 3) {
            const unsigned long parsed =
                std::strtoul(argv[2], nullptr, 10);
            if (parsed == 0 || parsed > 1000ul) {
                throw std::runtime_error(
                    "stability_repetitions must be 1..1000");
            }
            stability_repetitions =
                static_cast<unsigned int>(parsed);
        }

        std::cout
            << "Stage 2K-B F37X DLRM matrix regression\n"
            << "Access path: xclOpenContext + xclRegRead/xclRegWrite\n"
            << "DIRECTED_CASES=7\n"
            << "STABILITY_REPETITIONS="
            << stability_repetitions << "\n"
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
            << "case_sequence,case_name,category,layer_count,"
            << "initial_buffer,input_dim,final_out_dim,"
            << "output_index,expected,observed,result_meta,"
            << "result_status,result_count_after_pop,"
            << "first_result_latency_us,final_result_latency_us,"
            << "status\n";

        std::vector<MatrixCase> cases = directed_cases();
        for (std::size_t index = 0;
             index < cases.size();
             ++index) {
            validate_case(cases[index]);
        }

        MatrixCase repeated = stability_case();
        validate_case(repeated);

        unsigned int case_sequence = 0;
        unsigned int total_cases = 0;
        unsigned int total_outputs = 0;
        double first_latency_sum = 0.0;
        double final_latency_sum = 0.0;
        double first_latency_min = 0.0;
        double first_latency_max = 0.0;
        double final_latency_min = 0.0;
        double final_latency_max = 0.0;

        const auto execute_and_record =
            [&](const MatrixCase& test,
                const std::string& category) {
                const CaseResult result =
                    run_matrix_case(session, test);

                ++case_sequence;
                ++total_cases;
                total_outputs +=
                    static_cast<unsigned int>(
                        result.outputs.size());

                first_latency_sum +=
                    result.first_result_latency_us;
                final_latency_sum +=
                    result.final_result_latency_us;

                if (total_cases == 1u ||
                    result.first_result_latency_us <
                        first_latency_min) {
                    first_latency_min =
                        result.first_result_latency_us;
                }
                if (total_cases == 1u ||
                    result.first_result_latency_us >
                        first_latency_max) {
                    first_latency_max =
                        result.first_result_latency_us;
                }
                if (total_cases == 1u ||
                    result.final_result_latency_us <
                        final_latency_min) {
                    final_latency_min =
                        result.final_result_latency_us;
                }
                if (total_cases == 1u ||
                    result.final_result_latency_us >
                        final_latency_max) {
                    final_latency_max =
                        result.final_result_latency_us;
                }

                for (std::size_t output_index = 0;
                     output_index < result.outputs.size();
                     ++output_index) {
                    const OutputObservation& observation =
                        result.outputs[output_index];

                    csv
                        << case_sequence << ","
                        << test.name << ","
                        << category << ","
                        << test.layers.size() << ","
                        << test.initial_buffer << ","
                        << test.input.size() << ","
                        << test.expected.size() << ","
                        << observation.index << ","
                        << test.expected[output_index] << ","
                        << observation.value << ","
                        << hex32(observation.meta) << ","
                        << hex32(observation.status) << ","
                        << observation.result_count_after_pop << ","
                        << std::fixed << std::setprecision(3)
                        << result.first_result_latency_us << ","
                        << result.final_result_latency_us << ","
                        << "PASS\n";
                }

                std::cout
                    << "MATRIX_CASE_PASS"
                    << " sequence=" << case_sequence
                    << " name=" << test.name
                    << " category=" << category
                    << " layers=" << test.layers.size()
                    << " input_dim=" << test.input.size()
                    << " output_dim=" << test.expected.size()
                    << " initial_buffer="
                    << test.initial_buffer
                    << " first_us=" << std::fixed
                    << std::setprecision(3)
                    << result.first_result_latency_us
                    << " final_us="
                    << result.final_result_latency_us
                    << "\n";
            };

        for (std::size_t index = 0;
             index < cases.size();
             ++index) {
            execute_and_record(cases[index], "directed");
        }

        for (unsigned int repetition = 0;
             repetition < stability_repetitions;
             ++repetition) {
            MatrixCase test = repeated;
            test.name =
                "stability_17x3_two_chunks_" +
                std::to_string(repetition + 1u);
            execute_and_record(test, "stability");
        }

        csv.flush();
        if (!csv) {
            throw std::runtime_error(
                "failed while writing matrix CSV");
        }

        const double case_count =
            static_cast<double>(total_cases);

        std::cout
            << "DIRECTED_CASES=" << cases.size() << "\n"
            << "STABILITY_CASES="
            << stability_repetitions << "\n"
            << "TOTAL_CASES=" << total_cases << "\n"
            << "TOTAL_OUTPUTS=" << total_outputs << "\n"
            << "FIRST_RESULT_LATENCY_US_MIN="
            << std::fixed << std::setprecision(3)
            << first_latency_min << "\n"
            << "FIRST_RESULT_LATENCY_US_AVG="
            << (first_latency_sum / case_count) << "\n"
            << "FIRST_RESULT_LATENCY_US_MAX="
            << first_latency_max << "\n"
            << "FINAL_RESULT_LATENCY_US_MIN="
            << final_latency_min << "\n"
            << "FINAL_RESULT_LATENCY_US_AVG="
            << (final_latency_sum / case_count) << "\n"
            << "FINAL_RESULT_LATENCY_US_MAX="
            << final_latency_max << "\n"
            << "STAGE2K_B_MATRIX_REGRESSION_PASS"
            << " cases=" << total_cases
            << " outputs=" << total_outputs
            << " directed=" << cases.size()
            << " stability=" << stability_repetitions
            << "\n";

        return EXIT_SUCCESS;
    }
    catch (const std::exception& error) {
        std::cerr
            << "STAGE2K_B_MATRIX_REGRESSION_FAILED: "
            << error.what() << "\n";
        return EXIT_FAILURE;
    }
}
