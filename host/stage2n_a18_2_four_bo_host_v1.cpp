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
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <cstdlib>
#include <sys/mman.h>

namespace {

// Independent A18.2 Host. Do not treat this as A16/A17 with hardcoded rows.
// Memory indices come from a metadata-derived map; each BO is filled, synced,
// addressed, and released independently. Lookup indexes are AXI-Lite MMIO.
constexpr const char* kIpName =
    "dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1";
constexpr const char* kRejectedIpNeedle = "dlrm_a16_1";
constexpr const char* kRejectedA17Needle = "dlrm_a17_1";
constexpr unsigned kExpectedIpIndex = 0;
constexpr unsigned kBankCount = 4;
constexpr std::uint32_t kMemIndexMask = 0x00FFFFFFu;
constexpr std::size_t kPayloadBytes = 1024;
constexpr std::size_t kCaseCount = 5;
constexpr std::array<const char*, kCaseCount> kCaseNames = {{
    "baseline", "slot0_sensitivity", "slot1_sensitivity",
    "slot2_sensitivity", "slot3_sensitivity"
}};
// Locked from models/stage2n_a15_6/stage2n_a15_6_cases_v1.json and the accepted
// A16.2 board host.log. Local XSim result 36 is a different fixture and is not
// a board golden.
constexpr std::array<std::int32_t, kCaseCount> kLockedGoldens = {{
    -393, -392, -93, -689, -519
}};

constexpr std::uint32_t A_PIPE_CONTROL = 0x180;
constexpr std::uint32_t A_PIPE_VERSION = 0x184;
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
constexpr std::uint32_t A_BOTTOM_CYCLES = 0x218;
constexpr std::uint32_t A_INTERACTION_CYCLES = 0x21C;
constexpr std::uint32_t A_TOP_CYCLES = 0x220;
constexpr std::uint32_t A_TOTAL_CYCLES = 0x224;

constexpr std::uint32_t A_A15_CONTROL = 0x300;
constexpr std::array<std::uint32_t, kBankCount> A_TABLE_BASE_LO = {{
    0x304, 0x318, 0x320, 0x328
}};
constexpr std::array<std::uint32_t, kBankCount> A_TABLE_BASE_HI = {{
    0x308, 0x31C, 0x324, 0x32C
}};
constexpr std::array<std::uint32_t, kBankCount> A_LOOKUP_INDEX = {{
    0x330, 0x334, 0x338, 0x33C
}};
constexpr std::array<std::uint32_t, kBankCount> kDefaultLookupIndexes = {{
    37u, 38u, 39u, 40u
}};
constexpr std::uint32_t A_HBM_LOOKUP_CYCLES = 0x30C;
constexpr std::uint32_t A_FPGA_END_TO_END_CYCLES = 0x310;

constexpr std::uint32_t CMD_DESC = 0x0001;
constexpr std::uint32_t CMD_ACT = 0x0002;
constexpr std::uint32_t CMD_WEIGHT = 0x0008;
constexpr std::uint32_t CMD_BIAS = 0x0010;
constexpr std::uint32_t CMD_POP = 0x0040;
constexpr std::uint32_t CMD_ERROR_ACK = 0x0080;
constexpr std::uint32_t A15_CMD_START = 0x0001;
constexpr std::uint32_t A15_CMD_CLEAR = 0x0002;

constexpr std::uint32_t P_BUSY = 1u << 0;
constexpr std::uint32_t P_DONE = 1u << 1;
constexpr std::uint32_t P_VALID = 1u << 2;
constexpr std::uint32_t P_LAST = 1u << 3;
constexpr std::uint32_t P_CORE_ERROR = 1u << 4;
constexpr std::uint32_t P_WRAPPER_ERROR = 1u << 5;
constexpr std::uint32_t P_PENDING = 1u << 6;
constexpr std::uint32_t P_ANY_ERROR = 1u << 31;

constexpr std::uint32_t A15_DONE = 1u << 4;
constexpr std::uint32_t A15_ERROR = 1u << 5;
constexpr std::uint32_t A15_START_READY = 1u << 6;
constexpr std::uint32_t A15_RESULT_VALID = 1u << 7;
constexpr std::uint32_t A15_ANY_ERROR = 1u << 31;

constexpr std::uint32_t kExpectedPipeVersion = 0x00024E18;
constexpr std::uint32_t kExpectedBottomCycles = 322;
constexpr std::uint32_t kExpectedInteractionCycles = 100;
constexpr std::uint32_t kExpectedTopCycles = 744;
constexpr std::uint32_t kExpectedTotalCycles = 1174;
constexpr std::uint32_t kExpectedFinalTag = 4;
constexpr unsigned kPollTimeoutMs = 15000;

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

unsigned parse_unsigned(const std::string& text, const char* name)
{
    std::size_t consumed = 0;
    const unsigned long value = std::stoul(text, &consumed, 0);
    if (consumed != text.size() || value > std::numeric_limits<unsigned>::max())
        throw std::runtime_error(std::string("invalid ") + name + ": " + text);
    return static_cast<unsigned>(value);
}

std::int32_t parse_i32(const std::string& text, const char* name)
{
    std::size_t consumed = 0;
    const long value = std::stol(text, &consumed, 0);
    if (consumed != text.size() ||
        value < std::numeric_limits<std::int32_t>::min() ||
        value > std::numeric_limits<std::int32_t>::max())
        throw std::runtime_error(std::string("invalid ") + name + ": " + text);
    return static_cast<std::int32_t>(value);
}

std::array<std::uint32_t, kBankCount> load_lookup_indexes()
{
    const char* text = std::getenv("A18_2_LOOKUP_INDEXES");
    if (text == nullptr || *text == '\0')
        return kDefaultLookupIndexes;
    std::array<std::uint32_t, kBankCount> indexes = kDefaultLookupIndexes;
    std::string raw(text);
    std::size_t start = 0;
    for (unsigned slot = 0; slot < kBankCount; ++slot) {
        const std::size_t comma = (slot + 1u == kBankCount) ?
            std::string::npos : raw.find(',', start);
        const std::string token = (comma == std::string::npos) ?
            raw.substr(start) : raw.substr(start, comma - start);
        if (token.empty())
            throw std::runtime_error("A18_2_LOOKUP_INDEXES must be four decimal values");
        indexes[slot] = parse_unsigned(token, "lookup index");
        if (comma == std::string::npos) {
            if (slot + 1u != kBankCount)
                throw std::runtime_error("A18_2_LOOKUP_INDEXES must contain four values");
        } else {
            start = comma + 1;
        }
    }
    if (indexes != kDefaultLookupIndexes) {
        const char* allow = std::getenv("A18_2_ALLOW_NONDEFAULT_INDEXES");
        if (allow == nullptr || std::string(allow) != "yes")
            throw std::runtime_error(
                "non-default lookup indexes are not in the A18.2 five-case Host; "
                "keep 37,38,39,40 or generate software goldens first");
        throw std::runtime_error(
            "A18.2 Host still locks A15.6 goldens to rows 37-40; "
            "non-default board compares are not authorized in this file");
    }
    return indexes;
}

unsigned hex_nibble(char value)
{
    if (value >= '0' && value <= '9') return static_cast<unsigned>(value - '0');
    if (value >= 'a' && value <= 'f') return 10u + static_cast<unsigned>(value - 'a');
    if (value >= 'A' && value <= 'F') return 10u + static_cast<unsigned>(value - 'A');
    throw std::runtime_error("invalid UUID hexadecimal digit");
}

void parse_uuid(const std::string& text, xuid_t uuid)
{
    std::string compact;
    for (std::size_t index = 0; index < text.size(); ++index)
        if (text[index] != '-') compact.push_back(text[index]);
    if (compact.size() != 32u)
        throw std::runtime_error("xclbin UUID must contain 32 hexadecimal digits");
    for (std::size_t index = 0; index < 16u; ++index) {
        uuid[index] = static_cast<unsigned char>(
            (hex_nibble(compact[2u * index]) << 4) |
            hex_nibble(compact[2u * index + 1u]));
    }
}

std::string trim(const std::string& text)
{
    std::size_t begin = 0;
    while (begin < text.size() && (text[begin] == ' ' || text[begin] == '\t' ||
           text[begin] == '\r'))
        ++begin;
    std::size_t end = text.size();
    while (end > begin && (text[end - 1] == ' ' || text[end - 1] == '\t' ||
           text[end - 1] == '\r'))
        --end;
    return text.substr(begin, end - begin);
}

std::vector<std::uint8_t> read_file(const std::string& path)
{
    std::ifstream input(path.c_str(), std::ios::binary);
    if (!input) throw std::runtime_error("cannot open file: " + path);
    input.seekg(0, std::ios::end);
    const std::streamoff end = input.tellg();
    if (end < 0) throw std::runtime_error("cannot determine file size: " + path);
    input.seekg(0, std::ios::beg);
    std::vector<std::uint8_t> data(static_cast<std::size_t>(end));
    if (!data.empty())
        input.read(reinterpret_cast<char*>(&data[0]),
                   static_cast<std::streamsize>(data.size()));
    if (!input && !data.empty())
        throw std::runtime_error("failed to read complete file: " + path);
    return data;
}

struct MemMap {
    std::string uuid;
    std::array<unsigned, kBankCount> mem_index;
    std::array<std::string, kBankCount> tag;
};

MemMap load_mem_map(const std::string& path, const std::string& expected_uuid)
{
    std::ifstream input(path.c_str());
    if (!input) throw std::runtime_error("cannot open memory map: " + path);
    std::string line;
    if (!std::getline(input, line) || trim(line) != "A18_2_MEM_MAP_V1")
        throw std::runtime_error("memory map header is not A18_2_MEM_MAP_V1");
    MemMap map;
    bool seen_uuid = false;
    std::array<bool, kBankCount> seen_index = {{false, false, false, false}};
    std::array<bool, kBankCount> seen_tag = {{false, false, false, false}};
    while (std::getline(input, line)) {
        const std::string text = trim(line);
        if (text.empty() || text[0] == '#') continue;
        const std::size_t eq = text.find('=');
        if (eq == std::string::npos)
            throw std::runtime_error("malformed memory-map line: " + text);
        const std::string key = text.substr(0, eq);
        const std::string value = text.substr(eq + 1);
        if (key == "UUID") {
            map.uuid = value;
            seen_uuid = true;
        } else if (key == "KERNEL") {
            if (value != "dlrm_f37x_rtl_kernel_stage2n_a18_v1")
                throw std::runtime_error("memory map kernel is not A18");
        } else if (key == "CU") {
            if (value != "dlrm_a18_1")
                throw std::runtime_error("memory map CU is not dlrm_a18_1");
        } else if (key == "IP_NAME") {
            if (value != kIpName)
                throw std::runtime_error("memory map IP name is not A18");
            if (value.find(kRejectedIpNeedle) != std::string::npos)
                throw std::runtime_error("A16 CU identity is not accepted");
            if (value.find(kRejectedA17Needle) != std::string::npos)
                throw std::runtime_error("A17 CU identity is not accepted");
        } else if (key.size() >= 8 && key.compare(0, 3, "ARG") == 0 &&
                   key[3] >= '0' && key[3] <= '3') {
            // ARG0_TAG is 8 characters; ARG0_MEM_INDEX is 14. Do not require 14.
            const unsigned arg = static_cast<unsigned>(key[3] - '0');
            if (arg >= kBankCount)
                throw std::runtime_error("memory map argument out of range");
            if (key.find("_MEM_INDEX") != std::string::npos) {
                map.mem_index[arg] = parse_unsigned(value, "mem index");
                seen_index[arg] = true;
            } else if (key.find("_TAG") != std::string::npos) {
                map.tag[arg] = value;
                seen_tag[arg] = true;
            }
        }
    }
    if (!seen_uuid) throw std::runtime_error("memory map lacks UUID");
    if (map.uuid != expected_uuid)
        throw std::runtime_error("memory-map UUID does not match Host UUID argument");
    for (unsigned arg = 0; arg < kBankCount; ++arg) {
        if (!seen_index[arg] || !seen_tag[arg])
            throw std::runtime_error("memory map missing argument " +
                std::to_string(arg));
        const std::string expected_tag = "HBM[" + std::to_string(arg) + "]";
        if (map.tag[arg] != expected_tag)
            throw std::runtime_error("argument " + std::to_string(arg) +
                " tag is " + map.tag[arg] + ", expected " + expected_tag);
    }
    for (unsigned left = 0; left < kBankCount; ++left) {
        for (unsigned right = left + 1; right < kBankCount; ++right) {
            if (map.mem_index[left] == map.mem_index[right])
                throw std::runtime_error("duplicate memory index in map");
        }
    }
    return map;
}

class Reader
{
public:
    explicit Reader(const std::vector<std::uint8_t>& data) : data_(data) {}
    std::size_t offset() const { return offset_; }
    std::size_t size() const { return data_.size(); }
    std::uint8_t u8() { require(1); return data_[offset_++]; }
    std::int8_t i8() { return static_cast<std::int8_t>(u8()); }
    std::uint32_t u32()
    {
        require(4);
        std::uint32_t value = 0;
        for (unsigned byte = 0; byte < 4; ++byte)
            value |= static_cast<std::uint32_t>(data_[offset_ + byte]) << (8u * byte);
        offset_ += 4;
        return value;
    }
    std::int32_t i32() { return static_cast<std::int32_t>(u32()); }
    std::int16_t i16()
    {
        require(2);
        const std::uint16_t bits = static_cast<std::uint16_t>(data_[offset_]) |
            (static_cast<std::uint16_t>(data_[offset_ + 1]) << 8);
        offset_ += 2;
        return static_cast<std::int16_t>(bits);
    }
    std::string bytes(std::size_t count)
    {
        require(count);
        const std::string value(reinterpret_cast<const char*>(&data_[offset_]), count);
        offset_ += count;
        return value;
    }
private:
    void require(std::size_t count) const
    {
        if (count > data_.size() - offset_)
            throw std::runtime_error("truncated model asset");
    }
    const std::vector<std::uint8_t>& data_;
    std::size_t offset_ = 0;
};

struct Descriptor { std::uint32_t word0, word1, word2; };
struct ModelAsset {
    std::vector<Descriptor> descriptors;
    std::vector<std::int8_t> weights;
    std::vector<std::int32_t> biases;
    std::array<std::int16_t, 8> dense;
    std::uint32_t interaction_shift;
    std::uint32_t bottom_base, bottom_layers, top_base, top_layers;
};

ModelAsset load_model(const std::string& path)
{
    const std::vector<std::uint8_t> data = read_file(path);
    Reader reader(data);
    if (reader.bytes(8) != "F37XA156")
        throw std::runtime_error("A17 model magic mismatch; expected F37XA156");
    const std::uint32_t version = reader.u32();
    const std::uint32_t header_bytes = reader.u32();
    const std::uint32_t descriptor_count = reader.u32();
    const std::uint32_t weight_count = reader.u32();
    const std::uint32_t bias_count = reader.u32();
    const std::uint32_t dense_count = reader.u32();
    ModelAsset model;
    model.interaction_shift = reader.u32();
    model.bottom_base = reader.u32();
    model.bottom_layers = reader.u32();
    model.top_base = reader.u32();
    model.top_layers = reader.u32();
    const std::uint32_t sample_id = reader.u32();
    (void)reader.bytes(32);
    const std::string reserved = reader.bytes(8);
    if (version != 1u || header_bytes != 96u || descriptor_count != 5u ||
        weight_count != 1360u || bias_count != 73u || dense_count != 8u ||
        model.interaction_shift != 11u || model.bottom_base != 0u ||
        model.bottom_layers != 2u || model.top_base != 2u ||
        model.top_layers != 3u || sample_id != 0u ||
        reserved != std::string(8, '\0'))
        throw std::runtime_error("A17 model header contract mismatch");
    model.descriptors.resize(descriptor_count);
    for (std::size_t index = 0; index < model.descriptors.size(); ++index) {
        model.descriptors[index].word0 = reader.u32();
        model.descriptors[index].word1 = reader.u32();
        model.descriptors[index].word2 = reader.u32();
    }
    model.weights.resize(weight_count);
    for (std::size_t index = 0; index < model.weights.size(); ++index)
        model.weights[index] = reader.i8();
    model.biases.resize(bias_count);
    for (std::size_t index = 0; index < model.biases.size(); ++index)
        model.biases[index] = reader.i32();
    for (std::size_t index = 0; index < model.dense.size(); ++index)
        model.dense[index] = reader.i16();
    if (reader.offset() != reader.size())
        throw std::runtime_error("A18 model asset has trailing bytes");
    return model;
}

std::uint32_t pack_pair(std::int16_t low_value, std::int16_t high_value)
{
    return static_cast<std::uint32_t>(static_cast<std::uint16_t>(low_value)) |
        (static_cast<std::uint32_t>(static_cast<std::uint16_t>(high_value)) << 16);
}

class Hal
{
public:
    Hal(unsigned device_index, const std::string& expected_bdf,
        const std::string& uuid_text)
        : device_index_(device_index), expected_bdf_(expected_bdf)
    {
        parse_uuid(uuid_text, uuid_);
        handle_ = xclOpen(device_index_, nullptr, XCL_QUIET);
        if (!handle_)
            throw std::runtime_error("xclOpen failed for guarded device index");
        try {
            const int index = xclIPName2Index(handle_, kIpName);
            if (index < 0)
                throw std::runtime_error(
                    "xclIPName2Index failed for A18 CU; A16/A17 identity is rejected");
            ip_index_ = static_cast<unsigned>(index);
            if (ip_index_ != kExpectedIpIndex)
                throw std::runtime_error("unexpected A18 IP index");
            const int result = xclOpenContext(handle_, uuid_, ip_index_, false);
            if (result != 0)
                throw std::runtime_error("xclOpenContext failed: " + std::to_string(result));
            context_open_ = true;
        } catch (...) {
            xclClose(handle_); handle_ = nullptr; throw;
        }
    }
    ~Hal()
    {
        if (handle_ && context_open_) xclCloseContext(handle_, uuid_, ip_index_);
        if (handle_) xclClose(handle_);
    }
    Hal(const Hal&) = delete;
    Hal& operator=(const Hal&) = delete;
    xclDeviceHandle handle() const { return handle_; }
    unsigned ip_index() const { return ip_index_; }
    unsigned device_index() const { return device_index_; }
    const std::string& expected_bdf() const { return expected_bdf_; }
    void write(std::uint32_t offset, std::uint32_t value)
    {
        const int result = xclRegWrite(handle_, ip_index_, offset, value);
        if (result != 0)
            throw std::runtime_error("xclRegWrite failed at " + hex32(offset));
    }
    std::uint32_t read(std::uint32_t offset)
    {
        std::uint32_t value = 0;
        const int result = xclRegRead(handle_, ip_index_, offset, &value);
        if (result != 0)
            throw std::runtime_error("xclRegRead failed at " + hex32(offset));
        return value;
    }
private:
    xclDeviceHandle handle_ = nullptr;
    xuid_t uuid_ = {0};
    unsigned device_index_ = 0;
    unsigned ip_index_ = 0;
    std::string expected_bdf_;
    bool context_open_ = false;
};

class HbmBo
{
public:
    HbmBo(xclDeviceHandle handle, unsigned mem_index, const std::string& tag)
        : handle_(handle), requested_mem_index_(mem_index), tag_(tag)
    {
        // One BO, one mem index, one later sync. Do not reuse another bank's
        // mapping, paddr, or TO_DEVICE completion.
        bo_ = xclAllocBO(handle_, kPayloadBytes, 0, requested_mem_index_);
        if (bo_ == XRT_NULL_BO)
            throw std::runtime_error("xclAllocBO failed for " + tag_);
        try {
            std::memset(&properties_, 0, sizeof(properties_));
            if (xclGetBOProperties(handle_, bo_, &properties_) != 0)
                throw std::runtime_error("xclGetBOProperties failed for " + tag_);
            if (properties_.size < kPayloadBytes)
                throw std::runtime_error(tag_ + " BO is smaller than requested 1024 bytes");
            if ((properties_.flags & kMemIndexMask) != requested_mem_index_)
                throw std::runtime_error(tag_ + " BO memory index does not match metadata map");
            if ((properties_.paddr & 0xFu) != 0u)
                throw std::runtime_error(tag_ + " BO address is not 16-byte aligned");
            // A physical address of zero is valid; allocation failure is an
            // API/property failure, not paddr==0.
            mapped_ = xclMapBO(handle_, bo_, true);
            if (mapped_ == nullptr || mapped_ == MAP_FAILED)
                throw std::runtime_error("xclMapBO failed for " + tag_);
        } catch (...) { cleanup_noexcept(); throw; }
    }
    ~HbmBo() { cleanup_noexcept(); }
    void load_and_sync(const std::vector<std::uint8_t>& payload)
    {
        if (payload.size() != kPayloadBytes)
            throw std::runtime_error("HBM payload must be exactly 1024 bytes");
        std::memcpy(mapped_, &payload[0], payload.size());
        const int result = xclSyncBO(
            handle_, bo_, XCL_BO_SYNC_BO_TO_DEVICE, payload.size(), 0);
        if (result != 0)
            throw std::runtime_error("xclSyncBO(TO_DEVICE) failed for " + tag_);
        synced_ = true;
    }
    xclBufferHandle handle_id() const { return bo_; }
    std::uint64_t paddr() const { return properties_.paddr; }
    std::uint64_t size() const { return properties_.size; }
    unsigned mem_index() const { return properties_.flags & kMemIndexMask; }
    unsigned requested_mem_index() const { return requested_mem_index_; }
    const std::string& tag() const { return tag_; }
    bool synced() const { return synced_; }
    void release_checked()
    {
        if (bo_ == XRT_NULL_BO) return;
        int unmap_result = 0;
        if (mapped_ != nullptr && mapped_ != MAP_FAILED) {
            unmap_result = xclUnmapBO(handle_, bo_, mapped_);
            mapped_ = nullptr;
        }
        xclFreeBO(handle_, bo_); bo_ = XRT_NULL_BO;
        synced_ = false;
        if (unmap_result != 0) throw std::runtime_error("xclUnmapBO failed for " + tag_);
    }
private:
    void cleanup_noexcept()
    {
        if (bo_ == XRT_NULL_BO) return;
        if (mapped_ != nullptr && mapped_ != MAP_FAILED) {
            (void)xclUnmapBO(handle_, bo_, mapped_); mapped_ = nullptr;
        }
        xclFreeBO(handle_, bo_); bo_ = XRT_NULL_BO;
        synced_ = false;
    }
    xclDeviceHandle handle_ = nullptr;
    xclBufferHandle bo_ = XRT_NULL_BO;
    void* mapped_ = nullptr;
    xclBOProperties properties_;
    unsigned requested_mem_index_ = 0;
    std::string tag_;
    bool synced_ = false;
};

class FourBo
{
public:
    FourBo(xclDeviceHandle handle, const MemMap& map)
    {
        for (unsigned index = 0; index < kBankCount; ++index) {
            bos_[index].reset(new HbmBo(
                handle, map.mem_index[index], map.tag[index]));
            image_name_[index] = "unset";
        }
        for (unsigned left = 0; left < kBankCount; ++left) {
            for (unsigned right = left + 1; right < kBankCount; ++right) {
                if (bos_[left]->handle_id() == bos_[right]->handle_id())
                    throw std::runtime_error("two BOs share a handle");
                if (bos_[left]->mem_index() == bos_[right]->mem_index())
                    throw std::runtime_error("two BOs share a memory index");
                if (bos_[left]->paddr() != 0 &&
                    bos_[left]->paddr() == bos_[right]->paddr())
                    throw std::runtime_error("two non-zero BOs share a paddr");
            }
        }
    }
    // Rebuild every BO from the baseline image, then overlay only the
    // sensitive slot's table. Port i reads row 37+i from BOi, so slot-i
    // sensitivity must not copy the mutated table onto the other banks.
    void load_restored_case(const std::vector<std::uint8_t>& baseline,
        const std::vector<std::uint8_t>& case_image, int sensitive_slot,
        const char* case_name)
    {
        if (sensitive_slot < -1 || sensitive_slot >= static_cast<int>(kBankCount))
            throw std::runtime_error("sensitive slot out of range");
        for (unsigned index = 0; index < kBankCount; ++index) {
            const bool mutate =
                (sensitive_slot >= 0 && static_cast<int>(index) == sensitive_slot);
            bos_[index]->load_and_sync(mutate ? case_image : baseline);
            image_name_[index] = mutate ? case_name : "baseline";
        }
    }
    const char* image_name(unsigned index) const { return image_name_[index]; }
    void write_and_readback_bases(Hal& hal)
    {
        for (unsigned index = 0; index < kBankCount; ++index) {
            if (!bos_[index]->synced())
                throw std::runtime_error("START blocked: BO not synced for " +
                    bos_[index]->tag());
            const std::uint64_t paddr = bos_[index]->paddr();
            const std::uint32_t lo = static_cast<std::uint32_t>(paddr);
            const std::uint32_t hi = static_cast<std::uint32_t>(paddr >> 32);
            hal.write(A_TABLE_BASE_LO[index], lo);
            hal.write(A_TABLE_BASE_HI[index], hi);
            if (hal.read(A_TABLE_BASE_LO[index]) != lo ||
                hal.read(A_TABLE_BASE_HI[index]) != hi)
                throw std::runtime_error("BASE" + std::to_string(index) +
                    " readback mismatch");
        }
    }
    void write_and_readback_indexes(Hal& hal,
        const std::array<std::uint32_t, kBankCount>& indexes)
    {
        for (unsigned index = 0; index < kBankCount; ++index) {
            hal.write(A_LOOKUP_INDEX[index], indexes[index]);
            if (hal.read(A_LOOKUP_INDEX[index]) != indexes[index])
                throw std::runtime_error("LOOKUP_INDEX" + std::to_string(index) +
                    " readback mismatch");
        }
    }
    const HbmBo& at(unsigned index) const { return *bos_[index]; }
    void release_checked()
    {
        for (unsigned index = kBankCount; index > 0; --index)
            bos_[index - 1]->release_checked();
    }
private:
    std::array<std::unique_ptr<HbmBo>, kBankCount> bos_;
    std::array<const char*, kBankCount> image_name_;
};

void throw_on_pipe_error(Hal& hal, std::uint32_t status, const char* context)
{
    if (status & (P_CORE_ERROR | P_WRAPPER_ERROR | P_ANY_ERROR))
        throw std::runtime_error(std::string(context) + " pipe_status=" +
            hex32(status) + " error=" + hex32(hal.read(A_ERROR_CODE)));
}

void throw_on_a15_error(Hal& hal, std::uint32_t status, const char* context)
{
    if (status & (A15_ERROR | A15_ANY_ERROR))
        throw std::runtime_error(std::string(context) + " a15_status=" +
            hex32(status) + " error=" + hex32(hal.read(A_ERROR_CODE)));
}

template <typename Predicate>
std::uint32_t poll_register(Hal& hal, std::uint32_t address,
    Predicate predicate, const char* description)
{
    const std::chrono::steady_clock::time_point deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(kPollTimeoutMs);
    std::uint32_t value = 0;
    while (std::chrono::steady_clock::now() < deadline) {
        value = hal.read(address);
        if (address == A_PIPE_CONTROL) throw_on_pipe_error(hal, value, description);
        if (address == A_A15_CONTROL) throw_on_a15_error(hal, value, description);
        if (predicate(value)) return value;
        std::this_thread::sleep_for(std::chrono::microseconds(50));
    }
    throw std::runtime_error(std::string("timeout waiting for ") + description +
        " value=" + hex32(value));
}

void wait_command_idle(Hal& hal, const char* description)
{
    (void)poll_register(hal, A_PIPE_CONTROL,
        [](std::uint32_t value) { return (value & P_PENDING) == 0; },
        description);
}

void prepare_clean_idle(Hal& hal)
{
    std::uint32_t pipe = hal.read(A_PIPE_CONTROL);
    if (pipe & (P_CORE_ERROR | P_WRAPPER_ERROR | P_ANY_ERROR)) {
        hal.write(A_PIPE_CONTROL, CMD_ERROR_ACK);
        wait_command_idle(hal, "initial pipeline error acknowledgement");
    }
    pipe = hal.read(A_PIPE_CONTROL);
    if (pipe & P_VALID) {
        hal.write(A_PIPE_CONTROL, CMD_POP);
        wait_command_idle(hal, "initial stale result retirement");
    }
    std::uint32_t a15 = hal.read(A_A15_CONTROL);
    if (a15 & (A15_DONE | A15_ERROR | A15_ANY_ERROR | A15_RESULT_VALID)) {
        hal.write(A_A15_CONTROL, A15_CMD_CLEAR);
    }
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_START_READY) != 0; },
        "A18 clean idle/start-ready");
}

void write_descriptor(Hal& hal, std::uint32_t index, const Descriptor& descriptor)
{
    hal.write(A_DESC_INDEX, index);
    hal.write(A_DESC_WORD0, descriptor.word0);
    hal.write(A_DESC_WORD1, descriptor.word1);
    hal.write(A_DESC_WORD2, descriptor.word2);
    hal.write(A_PIPE_CONTROL, CMD_DESC);
    wait_command_idle(hal, "descriptor commit");
}

void write_weight(Hal& hal, std::uint32_t address, std::int8_t value)
{
    hal.write(A_WEIGHT_ADDR, address);
    hal.write(A_WEIGHT_DATA,
        static_cast<std::uint32_t>(static_cast<std::uint8_t>(value)));
    hal.write(A_PIPE_CONTROL, CMD_WEIGHT);
    wait_command_idle(hal, "weight commit");
}

void write_bias(Hal& hal, std::uint32_t address, std::int32_t value)
{
    if (value < -8388608 || value > 8388607)
        throw std::runtime_error("bias exceeds signed INT24");
    hal.write(A_BIAS_ADDR, address);
    hal.write(A_BIAS_DATA, static_cast<std::uint32_t>(value) & 0x00FFFFFFu);
    hal.write(A_PIPE_CONTROL, CMD_BIAS);
    wait_command_idle(hal, "bias commit");
}

void write_dense(Hal& hal, const std::array<std::int16_t, 8>& values)
{
    hal.write(A_ACT_BUFFER, 0u);
    hal.write(A_ACT_CHUNK, 0u);
    hal.write(A_ACT_MASK, 0x000000FFu);
    hal.write(A_ACT_DATA0, pack_pair(values[0], values[1]));
    hal.write(A_ACT_DATA1, pack_pair(values[2], values[3]));
    hal.write(A_ACT_DATA2, pack_pair(values[4], values[5]));
    hal.write(A_ACT_DATA3, pack_pair(values[6], values[7]));
    hal.write(A_ACT_DATA4, 0u); hal.write(A_ACT_DATA5, 0u);
    hal.write(A_ACT_DATA6, 0u); hal.write(A_ACT_DATA7, 0u);
    hal.write(A_PIPE_CONTROL, CMD_ACT);
    wait_command_idle(hal, "dense activation commit");
}

void configure_model(Hal& hal, const ModelAsset& model)
{
    for (std::size_t index = 0; index < model.descriptors.size(); ++index)
        write_descriptor(hal, static_cast<std::uint32_t>(index), model.descriptors[index]);
    for (std::size_t index = 0; index < model.weights.size(); ++index)
        write_weight(hal, static_cast<std::uint32_t>(index), model.weights[index]);
    for (std::size_t index = 0; index < model.biases.size(); ++index)
        write_bias(hal, static_cast<std::uint32_t>(index), model.biases[index]);
}

struct CaseResult {
    std::int32_t actual;
    std::uint32_t bottom_cycles, interaction_cycles, top_cycles, total_cycles;
    std::uint32_t hbm_lookup_cycles, fpga_end_to_end_cycles;
    std::int64_t pipeline_overhead_cycles;
    std::array<std::uint32_t, kBankCount> base_lo;
    std::array<std::uint32_t, kBankCount> base_hi;
    std::array<std::uint32_t, kBankCount> lookup_index;
};

void require_a13_regression(const CaseResult& result)
{
    // Read actual counters and report deltas. Frozen 322/100/744/1174 is a
    // same-config regression expectation, not a substitute for the measured
    // values. A18 lookup/e2e/residual are measured and are not required to
    // match A16.2 112/1289/3.
    if (result.bottom_cycles != kExpectedBottomCycles ||
        result.interaction_cycles != kExpectedInteractionCycles ||
        result.top_cycles != kExpectedTopCycles ||
        result.total_cycles != kExpectedTotalCycles)
        throw std::runtime_error(
            "A13 cycle regression failed actual=" +
            std::to_string(result.bottom_cycles) + "/" +
            std::to_string(result.interaction_cycles) + "/" +
            std::to_string(result.top_cycles) + "/" +
            std::to_string(result.total_cycles) +
            " expected=322/100/744/1174");
}

CaseResult run_case(Hal& hal, FourBo& bos, const ModelAsset& model,
    const std::vector<std::uint8_t>& baseline,
    const std::vector<std::uint8_t>& case_image, int sensitive_slot,
    const char* case_name, std::int32_t expected,
    const std::array<std::uint32_t, kBankCount>& lookup_indexes)
{
    write_dense(hal, model.dense);
    bos.load_restored_case(baseline, case_image, sensitive_slot, case_name);
    bos.write_and_readback_bases(hal);
    bos.write_and_readback_indexes(hal, lookup_indexes);

    hal.write(A_BOTTOM_CONFIG,
        (model.bottom_layers << 8) | model.bottom_base);
    hal.write(A_TOP_CONFIG, (model.top_layers << 8) | model.top_base);
    hal.write(A_PIPE_CONFIG, model.interaction_shift);
    const std::uint32_t ready = hal.read(A_CONFIG_READY);
    if ((ready & 0x1Bu) != 0x1Bu)
        throw std::runtime_error("model/dense configuration not ready: " + hex32(ready));
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_START_READY) != 0; },
        "A18 case start-ready");
    hal.write(A_A15_CONTROL, A15_CMD_START);

    const std::uint32_t pipe_status = poll_register(hal, A_PIPE_CONTROL,
        [](std::uint32_t value) { return (value & P_VALID) != 0; },
        "complete DLRM result");
    const std::uint32_t a15_during_result = hal.read(A_A15_CONTROL);
    throw_on_a15_error(hal, a15_during_result, "complete DLRM result");
    if ((a15_during_result & A15_RESULT_VALID) == 0u)
        throw std::runtime_error("A18 status does not expose result-valid");

    const std::uint32_t result_word = hal.read(A_RESULT_DATA);
    const std::int32_t actual = static_cast<std::int16_t>(result_word & 0xFFFFu);
    const std::uint32_t result_index = hal.read(A_RESULT_INDEX) & 0x3Fu;
    const std::uint32_t result_meta = hal.read(A_RESULT_META);
    const std::uint32_t loaded_mask = hal.read(A_EMB_MASK) & 0xFu;
    CaseResult result;
    result.actual = actual;
    result.bottom_cycles = hal.read(A_BOTTOM_CYCLES);
    result.interaction_cycles = hal.read(A_INTERACTION_CYCLES);
    result.top_cycles = hal.read(A_TOP_CYCLES);
    result.total_cycles = hal.read(A_TOTAL_CYCLES);
    result.hbm_lookup_cycles = hal.read(A_HBM_LOOKUP_CYCLES);
    result.fpga_end_to_end_cycles = hal.read(A_FPGA_END_TO_END_CYCLES);
    result.pipeline_overhead_cycles =
        static_cast<std::int64_t>(result.fpga_end_to_end_cycles) -
        static_cast<std::int64_t>(result.hbm_lookup_cycles) -
        static_cast<std::int64_t>(result.total_cycles);
    for (unsigned index = 0; index < kBankCount; ++index) {
        result.base_lo[index] = static_cast<std::uint32_t>(bos.at(index).paddr());
        result.base_hi[index] = static_cast<std::uint32_t>(bos.at(index).paddr() >> 32);
        if (hal.read(A_TABLE_BASE_LO[index]) != result.base_lo[index] ||
            hal.read(A_TABLE_BASE_HI[index]) != result.base_hi[index])
            throw std::runtime_error("BASE changed after START for bank " +
                std::to_string(index));
        result.lookup_index[index] = lookup_indexes[index];
        if (hal.read(A_LOOKUP_INDEX[index]) != lookup_indexes[index])
            throw std::runtime_error("LOOKUP_INDEX staging changed after START for slot " +
                std::to_string(index));
    }
    if (actual != expected) throw std::runtime_error("final result mismatch");
    if ((pipe_status & P_LAST) == 0u || (result_meta & 0x3u) != 0x3u)
        throw std::runtime_error("final result valid/last mismatch");
    if (result_index != 0u || ((result_meta >> 16) & 0xFFu) != kExpectedFinalTag)
        throw std::runtime_error("final result index/tag mismatch");
    if (loaded_mask != 0xFu) throw std::runtime_error("embedding loaded mask is not 0xF");
    require_a13_regression(result);
    if (result.hbm_lookup_cycles == 0u ||
        result.fpga_end_to_end_cycles == 0u)
        throw std::runtime_error("A18 latency counter is zero");
    if (result.pipeline_overhead_cycles < 0)
        throw std::runtime_error("negative FPGA latency accounting overhead");

    hal.write(A_PIPE_CONTROL, CMD_POP);
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_DONE) != 0; },
        "A18 terminal done");
    if (hal.read(A_RESULT_COUNT) != 1u)
        throw std::runtime_error("result count mismatch");
    const std::uint32_t phase = hal.read(A_PHASE_COUNTS);
    if (((phase >> 8) & 0xFu) != 8u || ((phase >> 16) & 0x1Fu) != 18u)
        throw std::runtime_error("bottom/interaction result count mismatch");
    hal.write(A_A15_CONTROL, A15_CMD_CLEAR);
    const std::uint32_t after_clear = poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_START_READY) != 0; },
        "A18 idle after clear");
    if ((after_clear & (A15_DONE | A15_RESULT_VALID | A15_ERROR)) != 0u)
        throw std::runtime_error("stale A18 status remains after CLEAR");
    return result;
}

void print_case(const std::string& prefix, const char* name,
    std::int32_t expected, const CaseResult& result, const FourBo& bos)
{
    std::cout << prefix << "NAME=" << name << "\n"
              << prefix << "EXPECTED_RESULT=" << expected << "\n"
              << prefix << "ACTUAL_RESULT=" << result.actual << "\n"
              << prefix << "XSIM_RESULT_36_NOT_USED=1\n"
              << prefix << "EMBEDDING_LOADED_MASK=0xF\n"
              << prefix << "BOTTOM_CYCLES_ACTUAL=" << result.bottom_cycles << "\n"
              << prefix << "INTERACTION_CYCLES_ACTUAL=" << result.interaction_cycles << "\n"
              << prefix << "TOP_CYCLES_ACTUAL=" << result.top_cycles << "\n"
              << prefix << "COMPUTE_TOTAL_CYCLES_ACTUAL=" << result.total_cycles << "\n"
              << prefix << "BOTTOM_CYCLES_EXPECTED=" << kExpectedBottomCycles << "\n"
              << prefix << "INTERACTION_CYCLES_EXPECTED=" << kExpectedInteractionCycles << "\n"
              << prefix << "TOP_CYCLES_EXPECTED=" << kExpectedTopCycles << "\n"
              << prefix << "COMPUTE_TOTAL_CYCLES_EXPECTED=" << kExpectedTotalCycles << "\n"
              << prefix << "BOTTOM_CYCLES_DELTA="
              << static_cast<std::int64_t>(result.bottom_cycles) - kExpectedBottomCycles << "\n"
              << prefix << "INTERACTION_CYCLES_DELTA="
              << static_cast<std::int64_t>(result.interaction_cycles) - kExpectedInteractionCycles << "\n"
              << prefix << "TOP_CYCLES_DELTA="
              << static_cast<std::int64_t>(result.top_cycles) - kExpectedTopCycles << "\n"
              << prefix << "COMPUTE_TOTAL_CYCLES_DELTA="
              << static_cast<std::int64_t>(result.total_cycles) - kExpectedTotalCycles << "\n"
              << prefix << "HBM_LOOKUP_CYCLES_ACTUAL=" << result.hbm_lookup_cycles << "\n"
              << prefix << "FPGA_END_TO_END_CYCLES_ACTUAL=" << result.fpga_end_to_end_cycles << "\n"
              << prefix << "PIPELINE_OVERHEAD_CYCLES_ACTUAL=" << result.pipeline_overhead_cycles << "\n"
              << prefix << "A16_2_LOOKUP_112_NOT_REQUIRED=1\n"
              << prefix << "A16_2_E2E_1289_NOT_REQUIRED=1\n"
              << prefix << "LATENCY_ACCOUNTING=RECORDED\n"
              << prefix << "COMPLETE_DLRM_RESULT=PASS\n";
    for (unsigned index = 0; index < kBankCount; ++index) {
        const HbmBo& bo = bos.at(index);
        std::cout                   << prefix << "BO" << index << "_TAG=" << bo.tag() << "\n"
                  << prefix << "BO" << index << "_IMAGE=" << bos.image_name(index) << "\n"
                  << prefix << "BO" << index << "_HANDLE=" << static_cast<unsigned long>(bo.handle_id()) << "\n"
                  << prefix << "BO" << index << "_MEM_INDEX=" << bo.mem_index() << "\n"
                  << prefix << "BO" << index << "_REQUESTED_SIZE=" << kPayloadBytes << "\n"
                  << prefix << "BO" << index << "_PROPERTIES_SIZE=" << bo.size() << "\n"
                  << prefix << "BO" << index << "_PADDR_HEX=" << hex64(bo.paddr()) << "\n"
                  << prefix << "BASE" << index << "_LO_HEX=" << hex32(result.base_lo[index]) << "\n"
                  << prefix << "BASE" << index << "_HI_HEX=" << hex32(result.base_hi[index]) << "\n"
                  << prefix << "LOOKUP_INDEX" << index << "=" << result.lookup_index[index] << "\n";
    }
}

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc != 16) {
            std::cerr << "usage: " << argv[0]
                << " <device-index> <expected-bdf> <xclbin-uuid> <model.bin>"
                << " <mem-map.txt> <case0.bin> <expected0> ... <case4.bin> <expected4>\n";
            return 2;
        }
        const unsigned device_index = parse_unsigned(argv[1], "device index");
        const std::string expected_bdf(argv[2]);
        const std::string uuid_text(argv[3]);
        const ModelAsset model = load_model(argv[4]);
        const MemMap mem_map = load_mem_map(argv[5], uuid_text);
        std::cout << "A18_2_HOST_MEM_MAP=PASS\n";
        for (unsigned arg = 0; arg < kBankCount; ++arg) {
            std::cout << "ARG" << arg << "_MEM_INDEX=" << mem_map.mem_index[arg]
                      << " ARG" << arg << "_TAG=" << mem_map.tag[arg] << "\n";
        }
        std::array<std::string, kCaseCount> table_paths;
        std::array<std::int32_t, kCaseCount> expected_results;
        for (std::size_t index = 0; index < kCaseCount; ++index) {
            table_paths[index] = argv[6 + 2 * index];
            expected_results[index] = parse_i32(
                argv[7 + 2 * index], "expected result");
            if (expected_results[index] != kLockedGoldens[index])
                throw std::runtime_error(
                    "golden lock mismatch for " + std::string(kCaseNames[index]) +
                    "; board goldens are A16.2/A15.6 values, not XSim 36");
            if (expected_results[index] == 36)
                throw std::runtime_error("XSim result 36 is not a board golden");
        }

        const std::array<std::uint32_t, kBankCount> lookup_indexes =
            load_lookup_indexes();
        Hal hal(device_index, expected_bdf, uuid_text);
        prepare_clean_idle(hal);
        if (hal.read(A_PIPE_VERSION) != kExpectedPipeVersion)
            throw std::runtime_error("A18 pipeline version mismatch; expected 0x00024E18");
        configure_model(hal, model);
        FourBo bos(hal.handle(), mem_map);

        std::cout << "A18_2_HOST_START=1\n"
                  << "TARGET_INDEX=" << hal.device_index() << "\n"
                  << "TARGET_BDF=" << hal.expected_bdf() << "\n"
                  << "XCLBIN_UUID=" << uuid_text << "\n"
                  << "IP_NAME=" << kIpName << "\n"
                  << "IP_INDEX=" << hal.ip_index() << "\n"
                  << "PIPE_VERSION_HEX=" << hex32(kExpectedPipeVersion) << "\n"
                  << "XSIM_RESULT_36_NOT_USED=1\n"
                  << "FUNCTIONAL_CASES=5\n"
                  << "DEFAULT_LOOKUP_INDEXES=37,38,39,40\n"
                  << "LOOKUP_INDEX0=" << lookup_indexes[0] << "\n"
                  << "LOOKUP_INDEX1=" << lookup_indexes[1] << "\n"
                  << "LOOKUP_INDEX2=" << lookup_indexes[2] << "\n"
                  << "LOOKUP_INDEX3=" << lookup_indexes[3] << "\n"
                  << "PER_BO_LAYOUT=restore_baseline_then_mutate_owned_slot_only\n"
                  << "BO_COUNT=4\n";
        for (unsigned index = 0; index < kBankCount; ++index) {
            const HbmBo& bo = bos.at(index);
            std::cout << "MAP_ARG" << index << "_TAG=" << bo.tag() << "\n"
                      << "MAP_ARG" << index << "_MEM_INDEX=" << bo.requested_mem_index() << "\n"
                      << "BO" << index << "_TAG=" << bo.tag() << "\n"
                      << "BO" << index << "_MEM_INDEX=" << bo.mem_index() << "\n"
                      << "BO" << index << "_HANDLE=" << static_cast<unsigned long>(bo.handle_id()) << "\n"
                      << "BO" << index << "_REQUESTED_SIZE=" << kPayloadBytes << "\n"
                      << "BO" << index << "_PROPERTIES_SIZE=" << bo.size() << "\n"
                      << "BO" << index << "_PADDR_HEX=" << hex64(bo.paddr()) << "\n";
        }
        std::cout << "MODEL_DESCRIPTOR_COUNT=" << model.descriptors.size() << "\n"
                  << "MODEL_WEIGHT_COUNT=" << model.weights.size() << "\n"
                  << "MODEL_BIAS_COUNT=" << model.biases.size() << "\n";

        const std::vector<std::uint8_t> baseline = read_file(table_paths[0]);
        std::int32_t previous_actual = 0;
        bool have_previous = false;
        for (std::size_t index = 0; index < kCaseCount; ++index) {
            const std::vector<std::uint8_t> case_image = read_file(table_paths[index]);
            const int sensitive_slot = (index == 0) ? -1 : static_cast<int>(index - 1);
            const CaseResult result = run_case(
                hal, bos, model, baseline, case_image, sensitive_slot,
                kCaseNames[index], expected_results[index], lookup_indexes);
            if (have_previous && result.actual == previous_actual &&
                expected_results[index] != previous_actual)
                throw std::runtime_error("stale result reused across cases");
            print_case("CASE" + std::to_string(index) + "_",
                kCaseNames[index], expected_results[index], result, bos);
            previous_actual = result.actual;
            have_previous = true;
        }

        const CaseResult repeat = run_case(
            hal, bos, model, baseline, baseline, -1,
            kCaseNames[0], expected_results[0], lookup_indexes);
        print_case("REPEAT_BASELINE_", kCaseNames[0],
            expected_results[0], repeat, bos);

        bos.release_checked();
        std::cout << "A18_2_BO_CLEANUP=PASS\n"
                  << "A18_2_ALL_FIVE_CASES=PASS\n"
                  << "A18_2_REPEAT_BASELINE=PASS\n"
                  << "A18_2_PHYSICAL_HBM_FUNCTIONAL_HOST=EXECUTED\n"
                  << "A18_2_PERFORMANCE=NOT_CLAIMED\n"
                  << "STAGE2N_A18_2_FOUR_BO_HOST_V1=PASS\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "STAGE2N_A18_2_FOUR_BO_HOST_V1_FAIL\n"
                  << "REASON=" << error.what() << "\n"
                  << "A18_2_BO_CLEANUP=ATTEMPTED_RAII\n";
        return 1;
    }
}
