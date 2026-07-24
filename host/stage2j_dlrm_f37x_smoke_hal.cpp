#include <xrt.h>
#include <experimental/xrt-next.h>

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
constexpr std::uint32_t CMD_CLEAR_DONE = 0x00000080;

constexpr std::uint32_t STATUS_BUSY = 1u << 0;
constexpr std::uint32_t STATUS_DONE = 1u << 1;
constexpr std::uint32_t STATUS_RESULT_VALID = 1u << 2;
constexpr std::uint32_t STATUS_CORE_ERROR = 1u << 4;
constexpr std::uint32_t STATUS_WRAPPER_ERROR = 1u << 5;
constexpr std::uint32_t STATUS_FINAL_BUFFER = 1u << 6;
constexpr std::uint32_t STATUS_COMMAND_PENDING = 1u << 7;

constexpr std::uint32_t EXPECTED_VERSION = 0x00024701;
constexpr std::int32_t EXPECTED_RESULT = 19;
constexpr std::uint32_t EXPECTED_RESULT_INDEX = 0;
constexpr std::uint32_t EXPECTED_LAYER_TAG = 1;

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

        /*
         * false means an exclusive context.  Register access through
         * xclRegRead/xclRegWrite requires exclusive ownership.
         */
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
                std::cerr
                    << "WARNING: xclCloseContext returned "
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

}  // namespace

int main()
{
    try {
        std::cout
            << "Stage 2J F37X DLRM low-level HAL smoke test\n"
            << "Access path: xclOpenContext + xclRegRead/xclRegWrite\n";

        HalSession session;

        const std::uint32_t version = session.read(ADDR_VERSION);
        const std::uint32_t initial_status =
            session.read(ADDR_CONTROL_STATUS);
        const std::uint32_t count_before =
            session.read(ADDR_RESULT_COUNT);

        std::cout << "VERSION=" << hex32(version) << "\n"
                  << "INITIAL_STATUS=" << hex32(initial_status) << "\n"
                  << "RESULT_COUNT_BEFORE=" << count_before << "\n";

        if (version != EXPECTED_VERSION) {
            throw std::runtime_error(
                "wrapper version mismatch: expected " +
                hex32(EXPECTED_VERSION) + ", got " + hex32(version));
        }

        throw_on_error_status(initial_status, "initial status check");

        if ((initial_status &
             (STATUS_BUSY | STATUS_COMMAND_PENDING |
              STATUS_RESULT_VALID)) != 0) {
            throw std::runtime_error(
                "kernel is not clean/idle before smoke test: status=" +
                hex32(initial_status));
        }

        session.write(ADDR_CONTROL_STATUS, CMD_CLEAR_DONE);
        poll_status(
            session,
            [](std::uint32_t status) {
                return (status & STATUS_DONE) == 0;
            },
            "clearing stale done state",
            std::chrono::milliseconds(1000));

        write_descriptor(
            session, 0, pack_descriptor(1, 1, 0, 0, 0, false));
        write_descriptor(
            session, 1, pack_descriptor(1, 1, 1, 1, 0, false));

        write_weight(session, 0, 2);
        write_weight(session, 1, 3);

        write_bias(session, 0, 1);
        write_bias(session, 1, -2);

        write_activation_lane0(session, 3);

        session.write(ADDR_LAYER_COUNT, 2);
        session.write(ADDR_INITIAL_BUFFER, 0);
        session.write(ADDR_CONTROL_STATUS, CMD_START);
        wait_command_idle(session, "waiting for start command acceptance");

        const std::uint32_t result_status = poll_status(
            session,
            [](std::uint32_t status) {
                return (status & STATUS_RESULT_VALID) != 0;
            },
            "waiting for final result",
            std::chrono::milliseconds(5000));

        const std::uint32_t result_raw =
            session.read(ADDR_RESULT_DATA);
        const std::uint32_t result_index_raw =
            session.read(ADDR_RESULT_INDEX);
        const std::uint32_t result_meta =
            session.read(ADDR_RESULT_META);

        const std::int32_t result =
            static_cast<std::int32_t>(result_raw);
        const std::uint32_t result_index =
            result_index_raw & 0x3FFu;
        const std::uint32_t layer_tag =
            (result_meta >> 8) & 0xFFu;

        std::cout << "RESULT_STATUS=" << hex32(result_status) << "\n"
                  << "RESULT_DATA=" << result << "\n"
                  << "RESULT_INDEX=" << result_index << "\n"
                  << "RESULT_META=" << hex32(result_meta) << "\n"
                  << "RESULT_LAYER_TAG=" << layer_tag << "\n";

        if (result != EXPECTED_RESULT) {
            throw std::runtime_error(
                "result mismatch: expected 19, got " +
                std::to_string(result));
        }
        if (result_index != EXPECTED_RESULT_INDEX) {
            throw std::runtime_error(
                "result index mismatch: expected 0, got " +
                std::to_string(result_index));
        }
        if ((result_meta & 0x3u) != 0x3u) {
            throw std::runtime_error(
                "result valid/last bits are not both set: meta=" +
                hex32(result_meta));
        }
        if (layer_tag != EXPECTED_LAYER_TAG) {
            throw std::runtime_error(
                "layer tag mismatch: expected 1, got " +
                std::to_string(layer_tag));
        }

        session.write(ADDR_CONTROL_STATUS, CMD_RESULT_POP);

        const std::uint32_t final_status = poll_status(
            session,
            [](std::uint32_t status) {
                return (status & STATUS_DONE) != 0 &&
                       (status & STATUS_RESULT_VALID) == 0;
            },
            "waiting for result pop and done",
            std::chrono::milliseconds(2000));

        if ((final_status & STATUS_FINAL_BUFFER) != 0) {
            throw std::runtime_error(
                "final activation-buffer selector is not zero: status=" +
                hex32(final_status));
        }

        const std::uint32_t count_after =
            session.read(ADDR_RESULT_COUNT);
        if (count_after != count_before + 1u) {
            throw std::runtime_error(
                "result count did not increment by one: before=" +
                std::to_string(count_before) + " after=" +
                std::to_string(count_after));
        }

        std::cout << "FINAL_STATUS=" << hex32(final_status) << "\n"
                  << "RESULT_COUNT_AFTER=" << count_after << "\n"
                  << "STAGE2J_HAL_BOARD_SMOKE_PASS result=19\n";
        return EXIT_SUCCESS;
    }
    catch (const std::exception& error) {
        std::cerr << "STAGE2J_HAL_BOARD_SMOKE_FAILED: "
                  << error.what() << "\n";
        return EXIT_FAILURE;
    }
}
