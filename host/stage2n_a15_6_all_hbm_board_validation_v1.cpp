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

constexpr const char* kIpName =
    "dlrm_f37x_rtl_kernel_stage2n_a15_v1:dlrm_a15_1";
constexpr unsigned kExpectedIpIndex = 0;
constexpr unsigned kExpectedMemIndex = 0;  // HBM[0] in accepted A15.5 xclbin
constexpr std::uint32_t kMemIndexMask = 0x00FFFFFFu;
constexpr std::size_t kPayloadBytes = 1024;
constexpr std::size_t kCaseCount = 5;
constexpr std::array<const char*, kCaseCount> kCaseNames = {{
    "baseline", "slot0_sensitivity", "slot1_sensitivity",
    "slot2_sensitivity", "slot3_sensitivity"
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
constexpr std::uint32_t A_TABLE_BASE_LO = 0x304;
constexpr std::uint32_t A_TABLE_BASE_HI = 0x308;

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

constexpr std::uint32_t kExpectedPipeVersion = 0x00024E13;
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
        throw std::runtime_error("A15.6 model magic mismatch");
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
    (void)reader.bytes(32);  // accepted Stage 2M source SHA256
    const std::string reserved = reader.bytes(8);
    if (version != 1u || header_bytes != 96u || descriptor_count != 5u ||
        weight_count != 1360u || bias_count != 73u || dense_count != 8u ||
        model.interaction_shift != 11u || model.bottom_base != 0u ||
        model.bottom_layers != 2u || model.top_base != 2u ||
        model.top_layers != 3u || sample_id != 0u ||
        reserved != std::string(8, '\0'))
        throw std::runtime_error("A15.6 model header contract mismatch");
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
        throw std::runtime_error("A15.6 model asset has trailing bytes");
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
            if (index < 0) throw std::runtime_error("xclIPName2Index failed for A15 CU");
            ip_index_ = static_cast<unsigned>(index);
            if (ip_index_ != kExpectedIpIndex)
                throw std::runtime_error("unexpected A15 IP index");
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
    explicit HbmBo(xclDeviceHandle handle) : handle_(handle)
    {
        bo_ = xclAllocBO(handle_, kPayloadBytes, 0, kExpectedMemIndex);
        if (bo_ == XRT_NULL_BO) throw std::runtime_error("xclAllocBO(HBM[0]) failed");
        try {
            std::memset(&properties_, 0, sizeof(properties_));
            if (xclGetBOProperties(handle_, bo_, &properties_) != 0)
                throw std::runtime_error("xclGetBOProperties failed");
            if (properties_.size < kPayloadBytes)
                throw std::runtime_error("HBM BO is smaller than 1024 bytes");
            if ((properties_.flags & kMemIndexMask) != kExpectedMemIndex)
                throw std::runtime_error("HBM BO memory index is not HBM[0]");
            if ((properties_.paddr & 0xFu) != 0u)
                throw std::runtime_error("HBM BO address is not 16-byte aligned");
            // A physical address of zero is valid on the accepted A14.7 path.
            mapped_ = xclMapBO(handle_, bo_, true);
            if (mapped_ == nullptr || mapped_ == MAP_FAILED)
                throw std::runtime_error("xclMapBO failed");
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
            throw std::runtime_error("xclSyncBO(TO_DEVICE) failed");
    }
    std::uint64_t paddr() const { return properties_.paddr; }
    std::uint64_t size() const { return properties_.size; }
    unsigned mem_index() const { return properties_.flags & kMemIndexMask; }
    void release_checked()
    {
        if (bo_ == XRT_NULL_BO) return;
        int unmap_result = 0;
        if (mapped_ != nullptr && mapped_ != MAP_FAILED) {
            unmap_result = xclUnmapBO(handle_, bo_, mapped_);
            mapped_ = nullptr;
        }
        xclFreeBO(handle_, bo_); bo_ = XRT_NULL_BO;
        if (unmap_result != 0) throw std::runtime_error("xclUnmapBO failed");
    }
private:
    void cleanup_noexcept()
    {
        if (bo_ == XRT_NULL_BO) return;
        if (mapped_ != nullptr && mapped_ != MAP_FAILED) {
            (void)xclUnmapBO(handle_, bo_, mapped_); mapped_ = nullptr;
        }
        xclFreeBO(handle_, bo_); bo_ = XRT_NULL_BO;
    }
    xclDeviceHandle handle_ = nullptr;
    xclBufferHandle bo_ = XRT_NULL_BO;
    void* mapped_ = nullptr;
    xclBOProperties properties_;
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
    if (a15 & (A15_DONE | A15_ERROR | A15_ANY_ERROR)) {
        hal.write(A_A15_CONTROL, A15_CMD_CLEAR);
    }
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_START_READY) != 0; },
        "A15 clean idle/start-ready");
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
    std::uint32_t table_base_lo, table_base_hi;
};

CaseResult run_case(Hal& hal, HbmBo& bo, const ModelAsset& model,
    const std::vector<std::uint8_t>& payload, std::int32_t expected)
{
    write_dense(hal, model.dense);
    bo.load_and_sync(payload);
    const std::uint64_t paddr = bo.paddr();
    const std::uint32_t base_lo = static_cast<std::uint32_t>(paddr);
    const std::uint32_t base_hi = static_cast<std::uint32_t>(paddr >> 32);
    hal.write(A_TABLE_BASE_LO, base_lo);
    hal.write(A_TABLE_BASE_HI, base_hi);
    if (hal.read(A_TABLE_BASE_LO) != base_lo || hal.read(A_TABLE_BASE_HI) != base_hi)
        throw std::runtime_error("TABLE_BASE readback mismatch");

    hal.write(A_BOTTOM_CONFIG,
        (model.bottom_layers << 8) | model.bottom_base);
    hal.write(A_TOP_CONFIG, (model.top_layers << 8) | model.top_base);
    hal.write(A_PIPE_CONFIG, model.interaction_shift);
    const std::uint32_t ready = hal.read(A_CONFIG_READY);
    if ((ready & 0x1Bu) != 0x1Bu)
        throw std::runtime_error("model/dense configuration not ready: " + hex32(ready));
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_START_READY) != 0; },
        "A15 case start-ready");
    hal.write(A_A15_CONTROL, A15_CMD_START);

    const std::uint32_t pipe_status = poll_register(hal, A_PIPE_CONTROL,
        [](std::uint32_t value) { return (value & P_VALID) != 0; },
        "complete DLRM result");
    const std::uint32_t a15_during_result = hal.read(A_A15_CONTROL);
    throw_on_a15_error(hal, a15_during_result, "complete DLRM result");
    if ((a15_during_result & A15_RESULT_VALID) == 0u)
        throw std::runtime_error("A15 status does not expose result-valid");

    const std::uint32_t result_word = hal.read(A_RESULT_DATA);
    const std::int32_t actual = static_cast<std::int16_t>(result_word & 0xFFFFu);
    const std::uint32_t result_index = hal.read(A_RESULT_INDEX) & 0x3Fu;
    const std::uint32_t result_meta = hal.read(A_RESULT_META);
    const std::uint32_t loaded_mask = hal.read(A_EMB_MASK) & 0xFu;
    CaseResult result = {
        actual,
        hal.read(A_BOTTOM_CYCLES), hal.read(A_INTERACTION_CYCLES),
        hal.read(A_TOP_CYCLES), hal.read(A_TOTAL_CYCLES),
        base_lo, base_hi
    };
    if (actual != expected) throw std::runtime_error("final result mismatch");
    if ((pipe_status & P_LAST) == 0u || (result_meta & 0x3u) != 0x3u)
        throw std::runtime_error("final result valid/last mismatch");
    if (result_index != 0u || ((result_meta >> 16) & 0xFFu) != kExpectedFinalTag)
        throw std::runtime_error("final result index/tag mismatch");
    if (loaded_mask != 0xFu) throw std::runtime_error("embedding loaded mask is not 0xF");
    if (result.bottom_cycles != kExpectedBottomCycles ||
        result.interaction_cycles != kExpectedInteractionCycles ||
        result.top_cycles != kExpectedTopCycles ||
        result.total_cycles != kExpectedTotalCycles)
        throw std::runtime_error("accepted A13 cycle counters changed");

    hal.write(A_PIPE_CONTROL, CMD_POP);
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_DONE) != 0; },
        "A15 terminal done");
    if (hal.read(A_RESULT_COUNT) != 1u)
        throw std::runtime_error("result count mismatch");
    const std::uint32_t phase = hal.read(A_PHASE_COUNTS);
    if (((phase >> 8) & 0xFu) != 8u || ((phase >> 16) & 0x1Fu) != 18u)
        throw std::runtime_error("bottom/interaction result count mismatch");
    hal.write(A_A15_CONTROL, A15_CMD_CLEAR);
    (void)poll_register(hal, A_A15_CONTROL,
        [](std::uint32_t value) { return (value & A15_START_READY) != 0; },
        "A15 idle after clear");
    return result;
}

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc != 15) {
            std::cerr << "usage: " << argv[0]
                << " <device-index> <expected-bdf> <xclbin-uuid> <model.bin>"
                << " <case0.bin> <expected0> ... <case4.bin> <expected4>\n";
            return 2;
        }
        const unsigned device_index = parse_unsigned(argv[1], "device index");
        const std::string expected_bdf(argv[2]);
        const std::string uuid_text(argv[3]);
        const ModelAsset model = load_model(argv[4]);
        std::array<std::string, kCaseCount> table_paths;
        std::array<std::int32_t, kCaseCount> expected_results;
        for (std::size_t index = 0; index < kCaseCount; ++index) {
            table_paths[index] = argv[5 + 2 * index];
            expected_results[index] = parse_i32(
                argv[6 + 2 * index], "expected result");
        }

        Hal hal(device_index, expected_bdf, uuid_text);
        prepare_clean_idle(hal);
        if (hal.read(A_PIPE_VERSION) != kExpectedPipeVersion)
            throw std::runtime_error("accepted A13 pipeline version mismatch");
        configure_model(hal, model);
        HbmBo bo(hal.handle());

        std::cout << "A15_6_HOST_START=1\n"
                  << "TARGET_INDEX=" << hal.device_index() << "\n"
                  << "TARGET_BDF=" << hal.expected_bdf() << "\n"
                  << "XCLBIN_UUID=" << uuid_text << "\n"
                  << "IP_NAME=" << kIpName << "\n"
                  << "IP_INDEX=" << hal.ip_index() << "\n"
                  << "HBM_BANK=HBM[0]\n"
                  << "HBM_MEMORY_INDEX=" << bo.mem_index() << "\n"
                  << "BO_SIZE_BYTES=" << bo.size() << "\n"
                  << "BO_PADDR_HEX=" << hex64(bo.paddr()) << "\n"
                  << "MODEL_DESCRIPTOR_COUNT=" << model.descriptors.size() << "\n"
                  << "MODEL_WEIGHT_COUNT=" << model.weights.size() << "\n"
                  << "MODEL_BIAS_COUNT=" << model.biases.size() << "\n";

        for (std::size_t index = 0; index < kCaseCount; ++index) {
            const std::vector<std::uint8_t> payload = read_file(table_paths[index]);
            const CaseResult result = run_case(
                hal, bo, model, payload, expected_results[index]);
            const std::string prefix = "CASE" + std::to_string(index) + "_";
            std::cout << prefix << "NAME=" << kCaseNames[index] << "\n"
                      << prefix << "EXPECTED_RESULT=" << expected_results[index] << "\n"
                      << prefix << "ACTUAL_RESULT=" << result.actual << "\n"
                      << prefix << "TABLE_BASE_LO_HEX=" << hex32(result.table_base_lo) << "\n"
                      << prefix << "TABLE_BASE_HI_HEX=" << hex32(result.table_base_hi) << "\n"
                      << prefix << "EMBEDDING_LOADED_MASK=0xF\n"
                      << prefix << "BOTTOM_CYCLES=" << result.bottom_cycles << "\n"
                      << prefix << "INTERACTION_CYCLES=" << result.interaction_cycles << "\n"
                      << prefix << "TOP_CYCLES=" << result.top_cycles << "\n"
                      << prefix << "TOTAL_CYCLES=" << result.total_cycles << "\n"
                      << prefix << "COMPLETE_DLRM_RESULT=PASS\n";
        }

        bo.release_checked();
        std::cout << "A15_6_BO_CLEANUP=PASS\n"
                  << "A15_6_ALL_FIVE_CASES=PASS\n"
                  << "A15_6_PHYSICAL_HBM_FUNCTIONAL_HOST=PASS\n"
                  << "A15_6_PERFORMANCE=NOT_CLAIMED\n"
                  << "STAGE2N_A15_6_ALL_HBM_BOARD_VALIDATION_V1=PASS\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "STAGE2N_A15_6_ALL_HBM_BOARD_VALIDATION_V1_FAIL\n"
                  << "REASON=" << error.what() << "\n"
                  << "A15_6_BO_CLEANUP=ATTEMPTED_RAII\n";
        return 1;
    }
}
