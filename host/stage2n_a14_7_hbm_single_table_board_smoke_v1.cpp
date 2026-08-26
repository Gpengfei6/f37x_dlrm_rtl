#include <xrt.h>
#include <experimental/xrt-next.h>

#include <array>
#include <chrono>
#include <cstdint>
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
#include <sys/mman.h>

namespace {

constexpr unsigned kDeviceIndex = 2;
constexpr const char* kTargetBdf = "0000:9b:00.1";
constexpr const char* kIpName =
    "dlrm_f37x_rtl_kernel_stage2n_a14_v2:dlrm_a14_1";
constexpr unsigned kExpectedIpIndex = 0;
constexpr unsigned kExpectedMemIndex = 0;  // linked HBM[0] memory-topology index
constexpr std::uint32_t kMemIndexMask = 0x00FFFFFFu;  // XRT 2020.2 xrt_mem.h
constexpr const char* kExpectedXclbinUuid =
    "6f29087c-9598-4e68-877a-cc4840d078b8";

constexpr std::uint32_t A_CONTROL = 0x000;
constexpr std::uint32_t A_LOOKUP_INDEX = 0x010;
constexpr std::uint32_t A_TABLE_BASE_LO = 0x018;
constexpr std::uint32_t A_TABLE_BASE_HI = 0x01C;
constexpr std::uint32_t A_RESULT0 = 0x020;
constexpr std::uint32_t A_RESULT1 = 0x024;
constexpr std::uint32_t A_RESULT2 = 0x028;
constexpr std::uint32_t A_RESULT3 = 0x02C;

constexpr std::uint32_t C_START_PENDING = 1u << 0;
constexpr std::uint32_t C_DONE = 1u << 1;
constexpr std::uint32_t C_IDLE = 1u << 2;
constexpr std::uint32_t C_READY = 1u << 3;
constexpr std::uint32_t C_RESPONSE_ERROR = 1u << 4;

constexpr std::size_t kRows = 64;
constexpr std::size_t kDim = 8;
constexpr std::size_t kRowBytes = 16;
constexpr std::size_t kPayloadBytes = 1024;
constexpr std::uint64_t kExpectedPayloadFnv1a64 = 0x40A53C3698B88325ULL;
constexpr std::uint32_t kDefaultLookupIndex = 37;
constexpr unsigned kPollLimit = 5000;

std::string hex32(std::uint32_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(8) << std::setfill('0') << value;
    return stream.str();
}

std::string hex64(std::uint64_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(16) << std::setfill('0') << value;
    return stream.str();
}

unsigned hex_nibble(char value)
{
    if (value >= '0' && value <= '9')
        return static_cast<unsigned>(value - '0');
    if (value >= 'a' && value <= 'f')
        return 10u + static_cast<unsigned>(value - 'a');
    if (value >= 'A' && value <= 'F')
        return 10u + static_cast<unsigned>(value - 'A');
    throw std::runtime_error("invalid UUID hexadecimal digit");
}

void parse_uuid(const std::string& text, xuid_t uuid)
{
    std::string compact;
    compact.reserve(32);
    for (std::size_t index = 0; index < text.size(); ++index) {
        if (text[index] != '-')
            compact.push_back(text[index]);
    }
    if (compact.size() != 32u)
        throw std::runtime_error("xclbin UUID must contain 32 hexadecimal digits");

    for (std::size_t index = 0; index < 16u; ++index) {
        uuid[index] = static_cast<unsigned char>(
            (hex_nibble(compact[2u * index]) << 4) |
            hex_nibble(compact[2u * index + 1u]));
    }
}

std::vector<std::uint8_t> read_file(const std::string& path)
{
    std::ifstream input(path.c_str(), std::ios::binary);
    if (!input)
        throw std::runtime_error("cannot open payload: " + path);
    input.seekg(0, std::ios::end);
    const std::streamoff end = input.tellg();
    if (end < 0)
        throw std::runtime_error("cannot determine payload size: " + path);
    input.seekg(0, std::ios::beg);
    std::vector<std::uint8_t> data(static_cast<std::size_t>(end));
    if (!data.empty())
        input.read(reinterpret_cast<char*>(&data[0]), static_cast<std::streamsize>(data.size()));
    if (!input && !data.empty())
        throw std::runtime_error("failed to read complete payload: " + path);
    return data;
}

std::uint64_t fnv1a64(const std::vector<std::uint8_t>& data)
{
    std::uint64_t value = 0xCBF29CE484222325ULL;
    for (std::size_t index = 0; index < data.size(); ++index) {
        value ^= static_cast<std::uint64_t>(data[index]);
        value *= 0x100000001B3ULL;
    }
    return value;
}

std::int16_t little_i16(const std::vector<std::uint8_t>& data, std::size_t offset)
{
    if (offset + 2 > data.size())
        throw std::runtime_error("int16 decode exceeds payload");
    const std::uint16_t bits =
        static_cast<std::uint16_t>(data[offset]) |
        (static_cast<std::uint16_t>(data[offset + 1]) << 8);
    return static_cast<std::int16_t>(bits);
}

std::array<std::int16_t, kDim> expected_row(
    const std::vector<std::uint8_t>& payload,
    std::uint32_t lookup_index)
{
    if (lookup_index >= kRows)
        throw std::runtime_error("lookup index must be in [0, 63]");
    std::array<std::int16_t, kDim> result = {{0, 0, 0, 0, 0, 0, 0, 0}};
    const std::size_t base = static_cast<std::size_t>(lookup_index) * kRowBytes;
    for (std::size_t lane = 0; lane < kDim; ++lane) {
        result[lane] = little_i16(payload, base + lane * 2);
        const std::int16_t formula = static_cast<std::int16_t>(
            static_cast<int>(lookup_index) * 8 + static_cast<int>(lane) - 256);
        if (result[lane] != formula)
            throw std::runtime_error("payload row does not match frozen A14 value formula");
    }
    return result;
}

std::array<std::int16_t, kDim> unpack_results(
    const std::array<std::uint32_t, 4>& words)
{
    std::array<std::int16_t, kDim> lanes = {{0, 0, 0, 0, 0, 0, 0, 0}};
    for (std::size_t word = 0; word < words.size(); ++word) {
        lanes[2 * word] = static_cast<std::int16_t>(words[word] & 0xFFFFu);
        lanes[2 * word + 1] = static_cast<std::int16_t>((words[word] >> 16) & 0xFFFFu);
    }
    return lanes;
}

std::uint32_t parse_lookup_index(const char* text)
{
    std::size_t consumed = 0;
    const std::string value(text);
    const unsigned long parsed = std::stoul(value, &consumed, 0);
    if (consumed != value.size() || parsed >= kRows)
        throw std::runtime_error("lookup index must be an integer in [0, 63]");
    return static_cast<std::uint32_t>(parsed);
}

class Hal
{
public:
    Hal()
    {
        parse_uuid(kExpectedXclbinUuid, uuid_);
        handle_ = xclOpen(kDeviceIndex, nullptr, XCL_QUIET);
        if (!handle_)
            throw std::runtime_error("xclOpen(index 2) failed");
        try {
            const int index = xclIPName2Index(handle_, kIpName);
            if (index < 0)
                throw std::runtime_error("xclIPName2Index failed for expected A14 CU");
            ip_index_ = static_cast<unsigned>(index);
            if (ip_index_ != kExpectedIpIndex)
                throw std::runtime_error("unexpected A14 IP index: " + std::to_string(ip_index_));
            const int context_result = xclOpenContext(handle_, uuid_, ip_index_, false);
            if (context_result != 0)
                throw std::runtime_error(
                    "xclOpenContext failed for accepted A14.6 UUID: " +
                    std::to_string(context_result));
            context_open_ = true;
        } catch (...) {
            xclClose(handle_);
            handle_ = nullptr;
            throw;
        }
    }

    ~Hal()
    {
        if (handle_ && context_open_)
            xclCloseContext(handle_, uuid_, ip_index_);
        if (handle_)
            xclClose(handle_);
    }

    xclDeviceHandle handle() const { return handle_; }
    unsigned ip_index() const { return ip_index_; }

    void write(std::uint32_t offset, std::uint32_t value)
    {
        const int result = xclRegWrite(handle_, ip_index_, offset, value);
        if (result != 0)
            throw std::runtime_error(
                "xclRegWrite failed at " + hex32(offset) + ": " + std::to_string(result));
    }

    std::uint32_t read(std::uint32_t offset)
    {
        std::uint32_t value = 0;
        const int result = xclRegRead(handle_, ip_index_, offset, &value);
        if (result != 0)
            throw std::runtime_error(
                "xclRegRead failed at " + hex32(offset) + ": " + std::to_string(result));
        return value;
    }

private:
    xclDeviceHandle handle_ = nullptr;
    xuid_t uuid_ = {0};
    unsigned ip_index_ = 0;
    bool context_open_ = false;
};

class HbmBo
{
public:
    explicit HbmBo(xclDeviceHandle handle)
        : handle_(handle)
    {
        bo_ = xclAllocBO(handle_, kPayloadBytes, 0, kExpectedMemIndex);
        if (bo_ == XRT_NULL_BO)
            throw std::runtime_error("xclAllocBO(HBM[0], 1024) failed");
        try {
            std::memset(&properties_, 0, sizeof(properties_));
            const int property_result = xclGetBOProperties(handle_, bo_, &properties_);
            if (property_result != 0)
                throw std::runtime_error(
                    "xclGetBOProperties failed: " + std::to_string(property_result));
            if (properties_.size < kPayloadBytes)
                throw std::runtime_error("allocated BO is smaller than 1024 bytes");
            const unsigned observed_mem_index = properties_.flags & kMemIndexMask;
            if (observed_mem_index != kExpectedMemIndex)
                throw std::runtime_error(
                    "BO memory index mismatch: " + std::to_string(observed_mem_index));
            if ((properties_.paddr & (kRowBytes - 1u)) != 0u)
                throw std::runtime_error("BO device address is not 16-byte aligned");
            if (properties_.paddr >
                std::numeric_limits<std::uint64_t>::max() - (kPayloadBytes - 1u))
                throw std::runtime_error("BO device-address range overflows 64 bits");

            mapped_ = xclMapBO(handle_, bo_, true);
            if (mapped_ == nullptr || mapped_ == MAP_FAILED)
                throw std::runtime_error("xclMapBO failed");
        } catch (...) {
            cleanup_noexcept();
            throw;
        }
    }

    ~HbmBo() { cleanup_noexcept(); }

    void load_and_sync(const std::vector<std::uint8_t>& payload)
    {
        if (payload.size() != kPayloadBytes)
            throw std::runtime_error("payload byte count is not 1024");
        std::memcpy(mapped_, &payload[0], payload.size());
        const int sync_result = xclSyncBO(
            handle_, bo_, XCL_BO_SYNC_BO_TO_DEVICE, payload.size(), 0);
        if (sync_result != 0)
            throw std::runtime_error("xclSyncBO(TO_DEVICE) failed: " + std::to_string(sync_result));
    }

    std::uint64_t paddr() const { return properties_.paddr; }
    std::uint32_t flags() const { return properties_.flags; }
    std::uint64_t size() const { return properties_.size; }

    void release_checked()
    {
        if (bo_ == XRT_NULL_BO)
            return;
        int unmap_result = 0;
        if (mapped_ != nullptr && mapped_ != MAP_FAILED) {
            unmap_result = xclUnmapBO(handle_, bo_, mapped_);
            mapped_ = nullptr;
        }
        xclFreeBO(handle_, bo_);
        bo_ = XRT_NULL_BO;
        if (unmap_result != 0)
            throw std::runtime_error("xclUnmapBO failed: " + std::to_string(unmap_result));
    }

private:
    void cleanup_noexcept()
    {
        if (bo_ == XRT_NULL_BO)
            return;
        if (mapped_ != nullptr && mapped_ != MAP_FAILED) {
            (void)xclUnmapBO(handle_, bo_, mapped_);
            mapped_ = nullptr;
        }
        xclFreeBO(handle_, bo_);
        bo_ = XRT_NULL_BO;
    }

    xclDeviceHandle handle_ = nullptr;
    xclBufferHandle bo_ = XRT_NULL_BO;
    void* mapped_ = nullptr;
    xclBOProperties properties_;
};

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc < 2 || argc > 3) {
            std::cerr << "usage: " << argv[0] << " <canonical-table.bin> [lookup-index]\n";
            return 2;
        }

        const std::string payload_path(argv[1]);
        const std::uint32_t lookup_index =
            argc == 3 ? parse_lookup_index(argv[2]) : kDefaultLookupIndex;
        const std::vector<std::uint8_t> payload = read_file(payload_path);
        if (payload.size() != kPayloadBytes)
            throw std::runtime_error("canonical payload must be exactly 1024 bytes");
        const std::uint64_t payload_fnv = fnv1a64(payload);
        if (payload_fnv != kExpectedPayloadFnv1a64)
            throw std::runtime_error(
                "canonical payload FNV1a64 mismatch: " + hex64(payload_fnv));
        const std::array<std::int16_t, kDim> expected = expected_row(payload, lookup_index);

        Hal hal;
        // A CONTROL read clears DONE.  If a previous completed lookup left a
        // stale DONE latched, the first read also reports READY=0; consume it
        // once and then require a clean idle/ready word.
        std::uint32_t pre_control = hal.read(A_CONTROL);
        if ((pre_control & C_DONE) != 0u)
            pre_control = hal.read(A_CONTROL);
        if ((pre_control & C_START_PENDING) != 0u)
            throw std::runtime_error("A14 start is already pending before smoke");
        if ((pre_control & C_RESPONSE_ERROR) != 0u)
            throw std::runtime_error("A14 reports a pre-existing response error");
        if ((pre_control & C_IDLE) == 0u || (pre_control & C_READY) == 0u)
            throw std::runtime_error("A14 CU is not idle/ready before smoke");

        HbmBo bo(hal.handle());
        bo.load_and_sync(payload);
        const std::uint64_t paddr = bo.paddr();
        const std::uint32_t table_base_lo = static_cast<std::uint32_t>(paddr & 0xFFFFFFFFULL);
        const std::uint32_t table_base_hi = static_cast<std::uint32_t>(paddr >> 32);

        hal.write(A_LOOKUP_INDEX, lookup_index);
        hal.write(A_TABLE_BASE_LO, table_base_lo);
        hal.write(A_TABLE_BASE_HI, table_base_hi);
        if (hal.read(A_LOOKUP_INDEX) != lookup_index)
            throw std::runtime_error("LOOKUP_INDEX readback mismatch");
        if (hal.read(A_TABLE_BASE_LO) != table_base_lo ||
            hal.read(A_TABLE_BASE_HI) != table_base_hi)
            throw std::runtime_error("TABLE_BASE readback mismatch");

        hal.write(A_CONTROL, 1u);

        std::uint32_t done_word = 0;
        bool done_seen = false;
        unsigned polls = 0;
        for (; polls < kPollLimit; ++polls) {
            const std::uint32_t control = hal.read(A_CONTROL);
            // CONTROL.done is read-to-clear.  The word from the first read that
            // sees DONE is authoritative; never try to observe DONE a second time.
            if ((control & C_DONE) != 0u) {
                done_word = control;
                done_seen = true;
                break;
            }
            if ((control & C_RESPONSE_ERROR) != 0u)
                throw std::runtime_error("A14 response error observed before DONE");
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        if (!done_seen)
            throw std::runtime_error("timed out waiting for read-to-clear CONTROL.done");
        if ((done_word & C_RESPONSE_ERROR) != 0u)
            throw std::runtime_error("A14 lookup completed with response error");

        const std::array<std::uint32_t, 4> words = {{
            hal.read(A_RESULT0),
            hal.read(A_RESULT1),
            hal.read(A_RESULT2),
            hal.read(A_RESULT3)
        }};
        const std::array<std::int16_t, kDim> actual = unpack_results(words);
        if (actual != expected)
            throw std::runtime_error("returned HBM row does not match canonical expected row");

        const std::uint32_t post_done_control = hal.read(A_CONTROL);
        if ((post_done_control & C_DONE) != 0u)
            throw std::runtime_error("CONTROL.done did not clear after authoritative read");
        if ((post_done_control & C_START_PENDING) != 0u ||
            (post_done_control & C_IDLE) == 0u ||
            (post_done_control & C_READY) == 0u ||
            (post_done_control & C_RESPONSE_ERROR) != 0u)
            throw std::runtime_error("A14 CU did not return to clean idle/ready state");

        const std::uint32_t bo_flags = bo.flags();
        const std::uint64_t bo_size = bo.size();
        bo.release_checked();

        std::cout << "A14_7_HOST_SMOKE=PASS\n";
        std::cout << "TARGET_INDEX=" << kDeviceIndex << "\n";
        std::cout << "TARGET_BDF=" << kTargetBdf << "\n";
        std::cout << "XCLBIN_UUID=" << kExpectedXclbinUuid << "\n";
        std::cout << "IP_NAME=" << kIpName << "\n";
        std::cout << "IP_INDEX=" << hal.ip_index() << "\n";
        std::cout << "HBM_MEMORY_INDEX=" << kExpectedMemIndex << "\n";
        std::cout << "BO_FLAGS_HEX=" << hex32(bo_flags) << "\n";
        std::cout << "BO_SIZE_BYTES=" << bo_size << "\n";
        std::cout << "BO_PADDR_HEX=" << hex64(paddr) << "\n";
        std::cout << "TABLE_BASE_LO_HEX=" << hex32(table_base_lo) << "\n";
        std::cout << "TABLE_BASE_HI_HEX=" << hex32(table_base_hi) << "\n";
        std::cout << "PAYLOAD_BYTES=" << payload.size() << "\n";
        std::cout << "PAYLOAD_FNV1A64=" << std::hex << std::setw(16)
                  << std::setfill('0') << payload_fnv << std::dec << "\n";
        std::cout << "LOOKUP_INDEX=" << lookup_index << "\n";
        std::cout << "CONTROL_PRE_START_HEX=" << hex32(pre_control) << "\n";
        std::cout << "CONTROL_DONE_WORD_HEX=" << hex32(done_word) << "\n";
        std::cout << "CONTROL_POST_DONE_HEX=" << hex32(post_done_control) << "\n";
        std::cout << "CONTROL_POLL_COUNT=" << (polls + 1u) << "\n";
        for (std::size_t word = 0; word < words.size(); ++word)
            std::cout << "RESULT" << word << "_HEX=" << hex32(words[word]) << "\n";
        for (std::size_t lane = 0; lane < actual.size(); ++lane) {
            std::cout << "EXPECTED_LANE" << lane << "=" << expected[lane] << "\n";
            std::cout << "ACTUAL_LANE" << lane << "=" << actual[lane] << "\n";
        }
        std::cout << "A14_7_RESULT_MATCH=PASS\n";
        std::cout << "A14_7_BO_RELEASED=PASS\n";
        std::cout << "A14_7_HOST_PASS=1\n";
        return 0;
    } catch (const std::exception& exc) {
        std::cerr << "A14_7_HOST_SMOKE=FAIL\n";
        std::cerr << "REASON=" << exc.what() << "\n";
        return 1;
    }
}
