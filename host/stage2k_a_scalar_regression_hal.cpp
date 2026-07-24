#include <xrt.h>
#include <experimental/xrt-next.h>

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
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

struct ScalarLayer {
    std::int8_t weight;
    std::int32_t bias;
    bool relu;
};

struct ScalarCase {
    std::string name;
    std::int16_t input;
    std::vector<ScalarLayer> layers;
    std::int32_t expected;
    bool stability_case;
};

struct CaseResult {
    std::int32_t result;
    std::uint32_t result_status;
    std::uint32_t result_meta;
    std::uint32_t result_index;
    std::uint32_t result_count_after;
    std::uint32_t final_status;
    double host_latency_us;
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

void recover_known_stale_bad_layer_count(
    HalSession& session,
    std::uint32_t status)
{
    if ((status & (STATUS_CORE_ERROR | STATUS_WRAPPER_ERROR)) == 0) {
        return;
    }

    const std::uint32_t core_error_code = (status >> 24) & 0xFu;
    const std::uint32_t wrapper_error_code = (status >> 28) & 0xFu;

    /*
     * The previous Stage 2K-A attempt intentionally reached a five-layer
     * case while this xclbin is compiled with MAX_LAYERS=4.  Error code 1 is
     * ERROR_BAD_LAYER_COUNT.  Recover only that exact, idle, non-pending
     * condition.  Any other error remains a hard stop.
     */
    /*
     * STATE_ERROR intentionally keeps BUSY asserted because the controller is
     * no longer in IDLE.  ERROR_ACK is precisely the command that releases
     * that state, so BUSY must not block this targeted recovery.  A pending
     * command or an unconsumed result remains unsafe.
     */
    const std::uint32_t unsafe_bits =
        STATUS_RESULT_VALID | STATUS_COMMAND_PENDING;

    if (core_error_code != 1u ||
        wrapper_error_code != 0u ||
        (status & unsafe_bits) != 0u) {
        throw_on_error_status(
            status,
            "unexpected pre-existing kernel error");
    }

    std::cout
        << "RECOVERING_STALE_ERROR"
        << " status=" << hex32(status)
        << " core_error_code=1"
        << " meaning=ERROR_BAD_LAYER_COUNT\n";

    session.write(ADDR_CONTROL_STATUS, CMD_ERROR_ACK);

    const auto deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(2000);
    std::uint32_t current = status;

    while (std::chrono::steady_clock::now() < deadline) {
        current = session.read(ADDR_CONTROL_STATUS);

        if ((current &
             (STATUS_CORE_ERROR | STATUS_WRAPPER_ERROR)) == 0) {
            std::cout
                << "STALE_ERROR_ACKNOWLEDGED"
                << " status=" << hex32(current) << "\n";
            return;
        }

        std::this_thread::sleep_for(
            std::chrono::microseconds(50));
    }

    throw std::runtime_error(
        "timeout acknowledging stale ERROR_BAD_LAYER_COUNT; "
        "last status=" + hex32(current));
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

        std::this_thread::sleep_for(std::chrono::microseconds(50));
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
    const std::uint32_t packed =
        static_cast<std::uint32_t>(value) & 0x00FFFFFFu;

    session.write(ADDR_BIAS_ADDRESS, address);
    session.write(ADDR_BIAS_DATA, packed);
    session.write(ADDR_CONTROL_STATUS, CMD_BIAS_COMMIT);
    wait_command_idle(session, "waiting for bias commit");
}

void write_activation_lane0(HalSession& session, std::int16_t value)
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

std::int32_t software_reference(const ScalarCase& test)
{
    std::int32_t value = test.input;

    for (std::size_t index = 0; index < test.layers.size(); ++index) {
        const ScalarLayer& layer = test.layers[index];
        value = value * static_cast<std::int32_t>(layer.weight)
              + layer.bias;

        if (layer.relu && value < 0) {
            value = 0;
        }

        if (value < -32768 || value > 32767) {
            throw std::runtime_error(
                "software case exceeds the unsaturated Stage 2K-A range: " +
                test.name);
        }
    }

    return value;
}

void prepare_clean_run(HalSession& session)
{
    const std::uint32_t status = session.read(ADDR_CONTROL_STATUS);
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
        "clearing done before case",
        std::chrono::milliseconds(1000));
}

CaseResult run_scalar_case(
    HalSession& session,
    const ScalarCase& test)
{
    if (test.layers.empty() || test.layers.size() > 255u) {
        throw std::runtime_error(
            "invalid layer count for case: " + test.name);
    }

    prepare_clean_run(session);

    for (std::size_t layer_index = 0;
         layer_index < test.layers.size();
         ++layer_index) {
        const ScalarLayer& layer = test.layers[layer_index];
        const std::uint32_t address =
            static_cast<std::uint32_t>(layer_index);

        write_descriptor(
            session,
            address,
            pack_descriptor(
                1, 1, address, address, 0, layer.relu));
        write_weight(session, address, layer.weight);
        write_bias(session, address, layer.bias);
    }

    write_activation_lane0(session, test.input);

    session.write(
        ADDR_LAYER_COUNT,
        static_cast<std::uint32_t>(test.layers.size()));
    session.write(ADDR_INITIAL_BUFFER, 0);

    const auto start_time = std::chrono::steady_clock::now();

    session.write(ADDR_CONTROL_STATUS, CMD_START);
    wait_command_idle(session, "waiting for start command acceptance");

    const std::uint32_t result_status = poll_status(
        session,
        [](std::uint32_t status) {
            return (status & STATUS_RESULT_VALID) != 0;
        },
        "waiting for scalar result",
        std::chrono::milliseconds(5000));

    const auto result_time = std::chrono::steady_clock::now();

    const std::int32_t result = static_cast<std::int32_t>(
        session.read(ADDR_RESULT_DATA));
    const std::uint32_t result_index =
        session.read(ADDR_RESULT_INDEX) & 0x3FFu;
    const std::uint32_t result_meta =
        session.read(ADDR_RESULT_META);
    const std::uint32_t layer_tag =
        (result_meta >> 8) & 0xFFu;

    const std::uint32_t expected_layer_tag =
        static_cast<std::uint32_t>(test.layers.size() - 1u);
    const bool expected_final_buffer =
        (test.layers.size() % 2u) != 0u;
    const bool observed_final_buffer =
        (result_status & STATUS_FINAL_BUFFER) != 0u;

    /*
     * Pop the result before validating its contents.  This guarantees that a
     * numerical assertion failure does not leave RESULT_VALID asserted and
     * does not strand the CU in a pending-result state.
     */
    session.write(ADDR_CONTROL_STATUS, CMD_RESULT_POP);

    const std::uint32_t final_status = poll_status(
        session,
        [](std::uint32_t status) {
            return (status & STATUS_DONE) != 0 &&
                   (status & STATUS_RESULT_VALID) == 0;
        },
        "waiting for result pop and done",
        std::chrono::milliseconds(2000));

    const std::uint32_t count_after =
        session.read(ADDR_RESULT_COUNT);

    /*
     * RESULT_COUNT is per-inference, not cumulative across separate starts.
     * Every Stage 2K-A scalar case has out_dim=1, so a completed inference
     * must report exactly one produced result.
     */
    const std::uint32_t expected_count_after = 1u;

    if (result != test.expected) {
        throw std::runtime_error(
            "result mismatch for " + test.name +
            ": expected " + std::to_string(test.expected) +
            ", got " + std::to_string(result));
    }
    if (result_index != 0u) {
        throw std::runtime_error(
            "result index mismatch for " + test.name +
            ": got " + std::to_string(result_index));
    }
    if ((result_meta & 0x3u) != 0x3u) {
        throw std::runtime_error(
            "result valid/last bits mismatch for " + test.name +
            ": meta=" + hex32(result_meta));
    }
    if (layer_tag != expected_layer_tag) {
        throw std::runtime_error(
            "layer tag mismatch for " + test.name +
            ": expected " + std::to_string(expected_layer_tag) +
            ", got " + std::to_string(layer_tag));
    }
    if (observed_final_buffer != expected_final_buffer) {
        throw std::runtime_error(
            "final buffer parity mismatch for " + test.name +
            ": expected " +
            std::to_string(expected_final_buffer ? 1 : 0) +
            ", got " +
            std::to_string(observed_final_buffer ? 1 : 0));
    }
    if (count_after != expected_count_after) {
        throw std::runtime_error(
            "result count mismatch for " + test.name +
            ": expected " + std::to_string(expected_count_after) +
            ", got " + std::to_string(count_after));
    }

    CaseResult output;
    output.result = result;
    output.result_status = result_status;
    output.result_meta = result_meta;
    output.result_index = result_index;
    output.result_count_after = count_after;
    output.final_status = final_status;
    output.host_latency_us =
        std::chrono::duration<double, std::micro>(
            result_time - start_time).count();
    return output;
}

std::vector<ScalarCase> directed_cases()
{
    std::vector<ScalarCase> cases;

    cases.push_back({
        "single_positive",
        3,
        {{2, 1, false}},
        7,
        false
    });

    cases.push_back({
        "single_negative_input",
        -4,
        {{3, 5, false}},
        -7,
        false
    });

    cases.push_back({
        "single_negative_weight",
        6,
        {{-2, 1, false}},
        -11,
        false
    });

    cases.push_back({
        "single_relu_clamp",
        -5,
        {{4, 3, true}},
        0,
        false
    });

    cases.push_back({
        "single_relu_positive",
        5,
        {{-2, 20, true}},
        10,
        false
    });

    cases.push_back({
        "two_layer_reference",
        3,
        {{2, 1, false}, {3, -2, false}},
        19,
        false
    });

    cases.push_back({
        "three_layer_signed",
        2,
        {{3, 1, false}, {-2, 5, false}, {-3, 2, false}},
        29,
        false
    });

    cases.push_back({
        "three_layer_relu_middle",
        -4,
        {{2, 1, true}, {5, 6, false}, {2, -1, false}},
        11,
        false
    });

    cases.push_back({
        "four_layer_alternating",
        1,
        {
            {2, 1, false},
            {3, -2, false},
            {-1, 4, false},
            {-2, 5, true}
        },
        11,
        false
    });

    return cases;
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
        unsigned int stability_repetitions = 100;

        if (argc == 3) {
            const unsigned long parsed =
                std::strtoul(argv[2], nullptr, 10);
            if (parsed == 0 || parsed > 10000ul) {
                throw std::runtime_error(
                    "stability_repetitions must be 1..10000");
            }
            stability_repetitions =
                static_cast<unsigned int>(parsed);
        }

        std::cout
            << "Stage 2K-A F37X DLRM scalar regression\n"
            << "Access path: xclOpenContext + xclRegRead/xclRegWrite\n"
            << "STABILITY_REPETITIONS="
            << stability_repetitions << "\n"
            << "CSV=" << csv_path << "\n";

        HalSession session;

        const std::uint32_t version =
            session.read(ADDR_VERSION);
        const std::uint32_t initial_status =
            session.read(ADDR_CONTROL_STATUS);
        const std::uint32_t initial_count =
            session.read(ADDR_RESULT_COUNT);

        std::cout << "VERSION=" << hex32(version) << "\n"
                  << "INITIAL_STATUS=" << hex32(initial_status) << "\n"
                  << "RESULT_COUNT_INITIAL=" << initial_count << "\n"
                  << "RESULT_COUNT_SEMANTICS=per_inference_output_count\n";

        if (version != EXPECTED_VERSION) {
            throw std::runtime_error(
                "wrapper version mismatch: expected " +
                hex32(EXPECTED_VERSION) + ", got " +
                hex32(version));
        }

        recover_known_stale_bad_layer_count(
            session, initial_status);

        const std::uint32_t ready_status =
            session.read(ADDR_CONTROL_STATUS);
        std::cout << "READY_STATUS="
                  << hex32(ready_status) << "\n";
        throw_on_error_status(
            ready_status, "ready status check");

        std::ofstream csv(csv_path.c_str());
        if (!csv) {
            throw std::runtime_error(
                "cannot open CSV output: " + csv_path);
        }

        csv
            << "sequence,case_name,category,input,layer_count,"
            << "expected,observed,result_index,result_meta,"
            << "result_status,final_status,result_count_after,"
            << "host_poll_latency_us,status\n";

        std::vector<ScalarCase> cases = directed_cases();

        for (std::size_t index = 0; index < cases.size(); ++index) {
            const std::int32_t reference =
                software_reference(cases[index]);
            if (reference != cases[index].expected) {
                throw std::runtime_error(
                    "internal expected-value error for " +
                    cases[index].name);
            }
        }

        ScalarCase stability = {
            "stability_two_layer_reference",
            3,
            {{2, 1, false}, {3, -2, false}},
            19,
            true
        };

        unsigned int sequence = 0;
        double total_latency_us = 0.0;
        double minimum_latency_us = 0.0;
        double maximum_latency_us = 0.0;
        unsigned int total_passed = 0;

        const auto execute_and_record =
            [&](const ScalarCase& test,
                const std::string& category) {
                const CaseResult result =
                    run_scalar_case(session, test);

                ++sequence;
                ++total_passed;

                total_latency_us += result.host_latency_us;
                if (sequence == 1 ||
                    result.host_latency_us < minimum_latency_us) {
                    minimum_latency_us = result.host_latency_us;
                }
                if (sequence == 1 ||
                    result.host_latency_us > maximum_latency_us) {
                    maximum_latency_us = result.host_latency_us;
                }

                csv
                    << sequence << ","
                    << test.name << ","
                    << category << ","
                    << test.input << ","
                    << test.layers.size() << ","
                    << test.expected << ","
                    << result.result << ","
                    << result.result_index << ","
                    << hex32(result.result_meta) << ","
                    << hex32(result.result_status) << ","
                    << hex32(result.final_status) << ","
                    << result.result_count_after << ","
                    << std::fixed << std::setprecision(3)
                    << result.host_latency_us << ",PASS\n";

                std::cout
                    << "CASE_PASS"
                    << " sequence=" << sequence
                    << " name=" << test.name
                    << " category=" << category
                    << " layers=" << test.layers.size()
                    << " input=" << test.input
                    << " result=" << result.result
                    << " count=" << result.result_count_after
                    << " latency_us=" << std::fixed
                    << std::setprecision(3)
                    << result.host_latency_us
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
            ScalarCase repeated = stability;
            repeated.name =
                "stability_two_layer_reference_" +
                std::to_string(repetition + 1u);
            execute_and_record(repeated, "stability");
        }

        csv.flush();
        if (!csv) {
            throw std::runtime_error(
                "failed while writing CSV output");
        }

        const double average_latency_us =
            total_latency_us /
            static_cast<double>(total_passed);

        const std::uint32_t final_count =
            session.read(ADDR_RESULT_COUNT);
        if (final_count != 1u) {
            throw std::runtime_error(
                "final per-inference result count mismatch: expected 1, got " +
                std::to_string(final_count));
        }

        std::cout
            << "DIRECTED_CASES=" << cases.size() << "\n"
            << "STABILITY_CASES=" << stability_repetitions << "\n"
            << "TOTAL_CASES=" << total_passed << "\n"
            << "RESULT_COUNT_FINAL=" << final_count << "\n"
            << "HOST_POLL_LATENCY_US_MIN="
            << std::fixed << std::setprecision(3)
            << minimum_latency_us << "\n"
            << "HOST_POLL_LATENCY_US_AVG="
            << average_latency_us << "\n"
            << "HOST_POLL_LATENCY_US_MAX="
            << maximum_latency_us << "\n"
            << "STAGE2K_A_SCALAR_REGRESSION_PASS"
            << " cases=" << total_passed
            << " directed=" << cases.size()
            << " stability=" << stability_repetitions
            << "\n";

        return EXIT_SUCCESS;
    }
    catch (const std::exception& error) {
        std::cerr
            << "STAGE2K_A_SCALAR_REGRESSION_FAILED: "
            << error.what() << "\n";
        return EXIT_FAILURE;
    }
}
