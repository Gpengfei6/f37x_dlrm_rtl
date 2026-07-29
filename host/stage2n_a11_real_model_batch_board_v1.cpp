#include <xrt.h>
#include <experimental/xrt-next.h>

#include <array>
#include <chrono>
#include <cstdint>
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

constexpr std::uint32_t EXPECTED_FLAGS = 0x7Fu;
constexpr std::uint32_t EXPECTED_SAMPLE_COUNT = 256u;
constexpr std::uint32_t EXPECTED_DESCRIPTOR_COUNT = 5u;
constexpr std::uint32_t EXPECTED_WEIGHT_COUNT = 1360u;
constexpr std::uint32_t EXPECTED_BIAS_COUNT = 73u;
constexpr std::uint32_t EXPECTED_EMBEDDING_TABLES = 4u;
constexpr std::uint32_t EXPECTED_EMBEDDING_DIM = 8u;
constexpr std::uint32_t EXPECTED_DENSE_DIM = 8u;
constexpr std::uint32_t EXPECTED_INTERACTION_DIM = 18u;
constexpr std::uint32_t EXPECTED_RESULT_DIM = 1u;
constexpr std::uint32_t EXPECTED_BOTTOM_LAYERS = 2u;
constexpr std::uint32_t EXPECTED_TOP_LAYERS = 3u;
constexpr std::uint32_t EXPECTED_INTERACTION_SHIFT = 11u;
constexpr std::uint32_t EXPECTED_FINAL_TAG = 4u;
constexpr std::uint32_t EXPECTED_CLASSIFICATION_CORRECT = 228u;
constexpr std::uint64_t EXPECTED_SOURCE_PAYLOAD_FNV1A64 =
    0x550ea17bcba314e5ULL;

constexpr unsigned ASSET_HEADER_BYTES = 128u;

std::string hex32(std::uint32_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(8)
           << std::setfill('0') << value;
    return stream.str();
}

std::string hex64(std::uint64_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(16)
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

std::uint64_t fnv1a64(
    const std::vector<std::uint8_t>& data,
    std::size_t begin)
{
    if (begin > data.size()) {
        throw std::runtime_error("FNV begin exceeds asset size");
    }

    std::uint64_t value = 0xCBF29CE484222325ULL;
    for (std::size_t index = begin; index < data.size(); ++index) {
        value ^= static_cast<std::uint64_t>(data[index]);
        value *= 0x100000001B3ULL;
    }
    return value;
}

class ByteReader
{
public:
    explicit ByteReader(const std::vector<std::uint8_t>& data)
        : data_(data)
    {
    }

    std::size_t offset() const { return offset_; }

    void seek(std::size_t value)
    {
        if (value > data_.size()) {
            throw std::runtime_error("asset seek exceeds file size");
        }
        offset_ = value;
    }

    std::uint8_t u8()
    {
        require(1);
        return data_[offset_++];
    }

    std::int8_t i8()
    {
        return static_cast<std::int8_t>(u8());
    }

    std::uint16_t u16()
    {
        require(2);
        const std::uint16_t value =
            static_cast<std::uint16_t>(data_[offset_]) |
            (static_cast<std::uint16_t>(data_[offset_ + 1]) << 8);
        offset_ += 2;
        return value;
    }

    std::int16_t i16()
    {
        return static_cast<std::int16_t>(u16());
    }

    std::uint32_t u32()
    {
        require(4);
        std::uint32_t value = 0;
        for (unsigned byte = 0; byte < 4; ++byte) {
            value |= static_cast<std::uint32_t>(
                         data_[offset_ + byte]) << (8u * byte);
        }
        offset_ += 4;
        return value;
    }

    std::int32_t i32()
    {
        return static_cast<std::int32_t>(u32());
    }

    std::uint64_t u64()
    {
        require(8);
        std::uint64_t value = 0;
        for (unsigned byte = 0; byte < 8; ++byte) {
            value |= static_cast<std::uint64_t>(
                         data_[offset_ + byte]) << (8u * byte);
        }
        offset_ += 8;
        return value;
    }

    std::string string(std::size_t count)
    {
        require(count);
        const std::string value(
            reinterpret_cast<const char*>(&data_[offset_]), count);
        offset_ += count;
        return value;
    }

    std::array<std::uint8_t, 8> bytes8()
    {
        require(8);
        std::array<std::uint8_t, 8> value = {{
            data_[offset_ + 0], data_[offset_ + 1],
            data_[offset_ + 2], data_[offset_ + 3],
            data_[offset_ + 4], data_[offset_ + 5],
            data_[offset_ + 6], data_[offset_ + 7]
        }};
        offset_ += 8;
        return value;
    }

private:
    void require(std::size_t count) const
    {
        if (count > data_.size() - offset_) {
            throw std::runtime_error(
                "truncated asset at offset " +
                std::to_string(offset_));
        }
    }

    const std::vector<std::uint8_t>& data_;
    std::size_t offset_ = 0;
};

struct Descriptor
{
    std::uint32_t word0;
    std::uint32_t word1;
    std::uint32_t word2;
};

struct Sample
{
    std::uint32_t sample_id;
    std::uint32_t label;
    std::array<std::uint32_t, 4> categorical_ids;
    std::array<std::int16_t, 8> dense;
    std::array<std::array<std::int16_t, 8>, 4> embeddings;
    std::array<std::int16_t, 8> expected_bottom;
    std::array<std::int16_t, 18> expected_interaction;
    std::int16_t expected_logit;
    std::uint32_t expected_prediction;
};

struct BatchAsset
{
    std::string model_name;
    std::uint64_t payload_fnv1a64;
    std::array<Descriptor, 5> descriptors;
    std::vector<std::int8_t> weights;
    std::vector<std::int32_t> biases;
    std::vector<Sample> samples;
};

std::vector<std::uint8_t> read_file(const std::string& path)
{
    std::ifstream input(path.c_str(), std::ios::binary);
    if (!input) {
        throw std::runtime_error("cannot open asset: " + path);
    }

    input.seekg(0, std::ios::end);
    const std::streamoff end = input.tellg();
    if (end <= 0) {
        throw std::runtime_error("asset is empty: " + path);
    }
    input.seekg(0, std::ios::beg);

    std::vector<std::uint8_t> data(
        static_cast<std::size_t>(end));
    input.read(
        reinterpret_cast<char*>(&data[0]),
        static_cast<std::streamsize>(data.size()));

    if (!input) {
        throw std::runtime_error("failed to read complete asset: " + path);
    }
    return data;
}

void require_equal(
    const char* name,
    std::uint64_t actual,
    std::uint64_t expected)
{
    if (actual != expected) {
        throw std::runtime_error(
            std::string(name) + " mismatch: actual=" +
            std::to_string(actual) + " expected=" +
            std::to_string(expected));
    }
}

BatchAsset load_asset(const std::string& path)
{
    const std::vector<std::uint8_t> data = read_file(path);
    if (data.size() < ASSET_HEADER_BYTES) {
        throw std::runtime_error("asset is smaller than 128-byte header");
    }

    ByteReader reader(data);
    const std::array<std::uint8_t, 8> magic = reader.bytes8();
    const std::array<std::uint8_t, 8> expected_magic = {{
        'F', '3', '7', 'X', 'P', 'B', '1', 0
    }};
    if (magic != expected_magic) {
        throw std::runtime_error("F37XPB1 asset magic mismatch");
    }

    const std::uint32_t version = reader.u32();
    const std::uint32_t header_bytes = reader.u32();
    const std::uint32_t flags = reader.u32();
    const std::uint32_t sample_count = reader.u32();
    const std::uint32_t descriptor_count = reader.u32();
    const std::uint32_t weight_count = reader.u32();
    const std::uint32_t bias_count = reader.u32();
    const std::uint32_t embedding_tables = reader.u32();
    const std::uint32_t embedding_dim = reader.u32();
    const std::uint32_t dense_dim = reader.u32();
    const std::uint32_t interaction_dim = reader.u32();
    const std::uint32_t result_dim = reader.u32();
    const std::uint32_t bottom_layers = reader.u32();
    const std::uint32_t top_layers = reader.u32();
    const std::uint32_t interaction_shift = reader.u32();

    const std::uint64_t payload_bytes = reader.u64();
    const std::uint64_t expected_payload_fnv = reader.u64();
    const std::uint64_t source_payload_fnv = reader.u64();
    const std::uint64_t source_sha_prefix = reader.u64();
    const std::uint64_t reserved_header = reader.u64();

    require_equal("asset version", version, 1u);
    require_equal("asset header bytes", header_bytes, ASSET_HEADER_BYTES);
    require_equal("asset flags", flags, EXPECTED_FLAGS);
    require_equal("sample count", sample_count, EXPECTED_SAMPLE_COUNT);
    require_equal(
        "descriptor count", descriptor_count, EXPECTED_DESCRIPTOR_COUNT);
    require_equal("weight count", weight_count, EXPECTED_WEIGHT_COUNT);
    require_equal("bias count", bias_count, EXPECTED_BIAS_COUNT);
    require_equal(
        "embedding tables",
        embedding_tables,
        EXPECTED_EMBEDDING_TABLES);
    require_equal(
        "embedding dimension",
        embedding_dim,
        EXPECTED_EMBEDDING_DIM);
    require_equal("dense dimension", dense_dim, EXPECTED_DENSE_DIM);
    require_equal(
        "interaction dimension",
        interaction_dim,
        EXPECTED_INTERACTION_DIM);
    require_equal("result dimension", result_dim, EXPECTED_RESULT_DIM);
    require_equal(
        "bottom layer count", bottom_layers, EXPECTED_BOTTOM_LAYERS);
    require_equal("top layer count", top_layers, EXPECTED_TOP_LAYERS);
    require_equal(
        "interaction shift",
        interaction_shift,
        EXPECTED_INTERACTION_SHIFT);
    require_equal("reserved header", reserved_header, 0u);
    require_equal(
        "source payload FNV1a64",
        source_payload_fnv,
        EXPECTED_SOURCE_PAYLOAD_FNV1A64);

    if (payload_bytes != data.size() - ASSET_HEADER_BYTES) {
        throw std::runtime_error("asset payload byte count mismatch");
    }

    const std::uint64_t observed_payload_fnv =
        fnv1a64(data, ASSET_HEADER_BYTES);
    if (observed_payload_fnv != expected_payload_fnv) {
        throw std::runtime_error(
            "asset payload FNV1a64 mismatch: actual=" +
            hex64(observed_payload_fnv) + " expected=" +
            hex64(expected_payload_fnv));
    }

    reader.seek(ASSET_HEADER_BYTES);

    const std::uint32_t name_bytes = reader.u32();
    if (name_bytes == 0u || name_bytes > 4096u) {
        throw std::runtime_error("invalid model-name byte count");
    }

    BatchAsset asset;
    asset.model_name = reader.string(name_bytes);
    asset.payload_fnv1a64 = observed_payload_fnv;

    for (std::size_t index = 0;
         index < asset.descriptors.size();
         ++index) {
        asset.descriptors[index].word0 = reader.u32();
        asset.descriptors[index].word1 = reader.u32();
        asset.descriptors[index].word2 = reader.u32();
    }

    asset.weights.reserve(EXPECTED_WEIGHT_COUNT);
    for (std::uint32_t index = 0;
         index < EXPECTED_WEIGHT_COUNT;
         ++index) {
        asset.weights.push_back(reader.i8());
    }

    asset.biases.reserve(EXPECTED_BIAS_COUNT);
    for (std::uint32_t index = 0;
         index < EXPECTED_BIAS_COUNT;
         ++index) {
        const std::int32_t value = reader.i32();
        if (value < -8388608 || value > 8388607) {
            throw std::runtime_error(
                "asset bias exceeds signed 24-bit range");
        }
        asset.biases.push_back(value);
    }

    asset.samples.reserve(EXPECTED_SAMPLE_COUNT);
    unsigned reference_correct = 0;

    for (std::uint32_t sample_index = 0;
         sample_index < EXPECTED_SAMPLE_COUNT;
         ++sample_index) {
        Sample sample;
        sample.sample_id = reader.u32();
        sample.label = reader.u32();

        if (sample.sample_id != sample_index) {
            throw std::runtime_error("asset sample ID sequence mismatch");
        }
        if (sample.label > 1u) {
            throw std::runtime_error("asset label is not binary");
        }

        for (std::size_t index = 0;
             index < sample.categorical_ids.size();
             ++index) {
            sample.categorical_ids[index] = reader.u32();
        }

        for (std::size_t index = 0;
             index < sample.dense.size();
             ++index) {
            sample.dense[index] = reader.i16();
        }

        for (std::size_t table = 0;
             table < sample.embeddings.size();
             ++table) {
            for (std::size_t lane = 0;
                 lane < sample.embeddings[table].size();
                 ++lane) {
                sample.embeddings[table][lane] = reader.i16();
            }
        }

        for (std::size_t index = 0;
             index < sample.expected_bottom.size();
             ++index) {
            sample.expected_bottom[index] = reader.i16();
        }

        for (std::size_t index = 0;
             index < sample.expected_interaction.size();
             ++index) {
            sample.expected_interaction[index] = reader.i16();
        }

        sample.expected_logit = reader.i16();
        sample.expected_prediction = reader.u32();
        const std::uint16_t sample_reserved = reader.u16();

        if (sample.expected_prediction > 1u) {
            throw std::runtime_error(
                "asset expected prediction is not binary");
        }
        if (sample_reserved != 0u) {
            throw std::runtime_error(
                "asset sample reserved field is nonzero");
        }

        const std::uint32_t prediction_from_logit =
            sample.expected_logit >= 0 ? 1u : 0u;
        if (prediction_from_logit != sample.expected_prediction) {
            throw std::runtime_error(
                "asset prediction/logit consistency failure");
        }

        if (sample.expected_prediction == sample.label) {
            ++reference_correct;
        }

        asset.samples.push_back(sample);
    }

    if (reader.offset() != data.size()) {
        throw std::runtime_error(
            "asset trailing-byte count is nonzero");
    }
    if (reference_correct != EXPECTED_CLASSIFICATION_CORRECT) {
        throw std::runtime_error(
            "asset reference classification count mismatch");
    }

    std::cout
        << "A11_ASSET_PARSE_PASS=1\n"
        << "A11_ASSET_MODEL_NAME=" << asset.model_name << "\n"
        << "A11_ASSET_BYTES=" << data.size() << "\n"
        << "A11_ASSET_PAYLOAD_FNV1A64="
        << hex64(asset.payload_fnv1a64) << "\n"
        << "A11_ASSET_SOURCE_SHA256_PREFIX_U64="
        << hex64(source_sha_prefix) << "\n"
        << "A11_ASSET_SAMPLE_COUNT="
        << asset.samples.size() << "\n"
        << "A11_ASSET_DESCRIPTOR_COUNT="
        << asset.descriptors.size() << "\n"
        << "A11_ASSET_WEIGHT_COUNT="
        << asset.weights.size() << "\n"
        << "A11_ASSET_BIAS_COUNT="
        << asset.biases.size() << "\n"
        << "A11_ASSET_REFERENCE_CORRECT="
        << reference_correct << "\n";

    return asset;
}

std::uint32_t pack_pair(
    std::int16_t low_value,
    std::int16_t high_value)
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
        if (ip_index_ != kExpectedIpIndex) {
            throw std::runtime_error(
                "unexpected IP index: " +
                std::to_string(ip_index_));
        }

        const int context_result =
            xclOpenContext(handle_, uuid_, ip_index_, false);
        if (context_result != 0) {
            throw std::runtime_error(
                "xclOpenContext(exclusive) failed: " +
                std::to_string(context_result));
        }
        context_open_ = true;

        std::cout
            << "HAL_DEVICE_INDEX=" << kDeviceIndex << "\n"
            << "HAL_TARGET_BDF=" << kTargetBdf << "\n"
            << "HAL_XCLBIN_UUID=" << uuid_string(uuid_) << "\n"
            << "HAL_IP_NAME=" << kIpName << "\n"
            << "HAL_IP_INDEX=" << ip_index_ << "\n"
            << "HAL_EXCLUSIVE_CONTEXT_OPEN=1\n";
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

void throw_on_error(
    Hal& hal,
    std::uint32_t status,
    const char* context)
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

void prepare_idle(Hal& hal)
{
    acknowledge_existing_error(hal);
    std::uint32_t status = hal.read(A_CTL);

    if (status & S_VALID) {
        const std::int32_t stale_result =
            static_cast<std::int32_t>(hal.read(A_RESULT_DATA));
        const std::uint32_t stale_meta = hal.read(A_RESULT_META);

        std::cout
            << "PIPELINE_STALE_RESULT_DETECTED=1\n"
            << "PIPELINE_STALE_RESULT="
            << stale_result << "\n"
            << "PIPELINE_STALE_TAG="
            << ((stale_meta >> 16) & 0xFFu) << "\n";

        hal.write(A_CTL, CMD_POP);
        status = poll_status(
            hal,
            [](std::uint32_t value) {
                return
                    (value &
                     (S_BUSY | S_VALID | S_PENDING)) == 0;
            },
            "stale result release",
            10000);

        std::cout
            << "PIPELINE_STALE_RESULT_POPPED=1\n"
            << "PIPELINE_STATUS_AFTER_STALE_POP="
            << hex32(status) << "\n";
    }

    if (status & S_BUSY) {
        throw std::runtime_error(
            "pipeline remains busy without releasable result: " +
            hex32(status));
    }

    if (status & S_DONE) {
        hal.write(A_CTL, CMD_CLEAR_DONE);
        status = poll_status(
            hal,
            [](std::uint32_t value) {
                return (value & (S_DONE | S_PENDING)) == 0;
            },
            "stale done clear",
            2000);
    }

    throw_on_error(hal, status, "prepare idle");
    if (status & (S_BUSY | S_VALID | S_PENDING | S_DONE)) {
        throw std::runtime_error(
            "pipeline is not idle after cleanup: " +
            hex32(status));
    }
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
    if (value < -8388608 || value > 8388607) {
        throw std::runtime_error("bias exceeds signed 24-bit range");
    }

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

void write_dense_input(
    Hal& hal,
    const std::array<std::int16_t, 8>& values)
{
    hal.write(A_ACT_BUFFER, 0u);
    hal.write(A_ACT_CHUNK, 0u);
    hal.write(A_ACT_MASK, 0x000000FFu);
    hal.write(A_ACT_DATA0, pack_pair(values[0], values[1]));
    hal.write(A_ACT_DATA1, pack_pair(values[2], values[3]));
    hal.write(A_ACT_DATA2, pack_pair(values[4], values[5]));
    hal.write(A_ACT_DATA3, pack_pair(values[6], values[7]));
    hal.write(A_ACT_DATA4, 0u);
    hal.write(A_ACT_DATA5, 0u);
    hal.write(A_ACT_DATA6, 0u);
    hal.write(A_ACT_DATA7, 0u);
    hal.write(A_CTL, CMD_ACT);
    wait_command_idle(hal, "dense activation commit");
}

void configure_static_model(Hal& hal, const BatchAsset& asset)
{
    for (std::size_t index = 0;
         index < asset.descriptors.size();
         ++index) {
        write_descriptor(
            hal,
            static_cast<std::uint32_t>(index),
            asset.descriptors[index]);
    }

    for (std::size_t index = 0;
         index < asset.weights.size();
         ++index) {
        write_weight(
            hal,
            static_cast<std::uint32_t>(index),
            asset.weights[index]);

        if ((index + 1u) % 256u == 0u ||
            index + 1u == asset.weights.size()) {
            std::cout
                << "A11_WEIGHT_PROGRAM_PROGRESS="
                << (index + 1u) << "/"
                << asset.weights.size() << "\n";
        }
    }

    for (std::size_t index = 0;
         index < asset.biases.size();
         ++index) {
        write_bias(
            hal,
            static_cast<std::uint32_t>(index),
            asset.biases[index]);
    }

    std::cout
        << "A11_STATIC_MODEL_CONFIGURATION_PASS=1\n"
        << "A11_DESCRIPTOR_COUNT="
        << asset.descriptors.size() << "\n"
        << "A11_WEIGHT_COUNT="
        << asset.weights.size() << "\n"
        << "A11_BIAS_COUNT="
        << asset.biases.size() << "\n";
}

void configure_sample(Hal& hal, const Sample& sample)
{
    for (std::size_t index = 0;
         index < sample.embeddings.size();
         ++index) {
        write_embedding(
            hal,
            static_cast<std::uint32_t>(index),
            sample.embeddings[index]);
    }

    write_dense_input(hal, sample.dense);

    const std::uint32_t embedding_mask = hal.read(A_EMB_MASK);
    if ((embedding_mask & 0xFu) != 0xFu) {
        throw std::runtime_error(
            "embedding mask mismatch: " +
            hex32(embedding_mask));
    }
}

void start_pipeline(Hal& hal)
{
    hal.write(
        A_BOTTOM_CONFIG,
        (EXPECTED_BOTTOM_LAYERS << 8) | 0u);
    hal.write(
        A_TOP_CONFIG,
        (EXPECTED_TOP_LAYERS << 8) | EXPECTED_BOTTOM_LAYERS);
    hal.write(A_PIPE_CONFIG, EXPECTED_INTERACTION_SHIFT);

    const std::uint32_t start_status = poll_status(
        hal,
        [](std::uint32_t status) {
            return
                (status & S_START_READY) != 0 &&
                (status & S_PENDING) == 0;
        },
        "configured pipeline start ready",
        2000);

    const std::uint32_t ready = hal.read(A_CONFIG_READY);
    if ((ready & 0x3Fu) != 0x3Fu) {
        throw std::runtime_error(
            "configuration ready mismatch before start: " +
            hex32(ready));
    }

    hal.write(A_CTL, CMD_START);
    wait_command_idle(hal, "pipeline start");

    (void)start_status;
}

struct RunResult
{
    std::int32_t logit;
    std::uint32_t prediction;
    std::uint32_t result_index;
    std::uint32_t result_tag;
    std::uint32_t bottom_count;
    std::uint32_t interaction_count;
};

RunResult run_sample(
    Hal& hal,
    const Sample& sample)
{
    prepare_idle(hal);
    configure_sample(hal, sample);
    start_pipeline(hal);

    std::uint32_t status = poll_status(
        hal,
        [](std::uint32_t value) {
            return (value & S_VALID) != 0;
        },
        "pipeline sample result",
        10000);

    RunResult result;
    result.logit =
        static_cast<std::int32_t>(hal.read(A_RESULT_DATA));
    result.result_index =
        hal.read(A_RESULT_INDEX) & 0x3Fu;

    const std::uint32_t result_meta = hal.read(A_RESULT_META);
    result.result_tag = (result_meta >> 16) & 0xFFu;
    result.prediction = result.logit >= 0 ? 1u : 0u;

    if ((status & S_LAST) == 0u ||
        (result_meta & 0x3u) != 0x3u) {
        throw std::runtime_error(
            "result valid/last metadata mismatch");
    }
    if (result.result_index != 0u) {
        throw std::runtime_error("result index mismatch");
    }
    if (result.result_tag != EXPECTED_FINAL_TAG) {
        throw std::runtime_error("result descriptor tag mismatch");
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

    result.bottom_count = (phase_counts >> 8) & 0xFu;
    result.interaction_count = (phase_counts >> 16) & 0x1Fu;

    if (result_count != 1u) {
        throw std::runtime_error("result count mismatch");
    }
    if (result.bottom_count != EXPECTED_EMBEDDING_DIM) {
        throw std::runtime_error("bottom output count mismatch");
    }
    if (result.interaction_count != EXPECTED_INTERACTION_DIM) {
        throw std::runtime_error("interaction output count mismatch");
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

    return result;
}

void write_csv_header(std::ofstream& output)
{
    output
        << "sample_id,label,expected_logit,fpga_logit,"
        << "expected_prediction,fpga_prediction,"
        << "logit_exact,prediction_exact,"
        << "classification_correct,result_index,result_tag,"
        << "bottom_count,interaction_count\n";
}

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc != 3) {
            std::cerr
                << "Usage: " << argv[0]
                << " <stage2n_a11_real_model_batch_v2.f37xpb>"
                << " <output.csv>\n";
            return 2;
        }

        const std::string asset_path = argv[1];
        const std::string output_csv_path = argv[2];

        std::cout
            << "Stage 2N-A11 256-sample automatic-pipeline Host v1\n"
            << "Access=xclOpenContext+xclRegRead+xclRegWrite\n"
            << "ASSET_PATH=" << asset_path << "\n"
            << "OUTPUT_CSV=" << output_csv_path << "\n"
            << "CLAIM_BOUNDARY=deterministic synthetic Stage 2M "
            << "trained-model regression; not real Criteo evidence\n";

        const BatchAsset asset = load_asset(asset_path);

        std::ofstream output(output_csv_path.c_str());
        if (!output) {
            throw std::runtime_error(
                "cannot open output CSV: " + output_csv_path);
        }
        write_csv_header(output);

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
            throw std::runtime_error("legacy MLP version mismatch");
        }
        if (interaction_version != EXPECTED_INT_VERSION) {
            throw std::runtime_error("interaction version mismatch");
        }
        if (pipeline_version != EXPECTED_PIPE_VERSION) {
            throw std::runtime_error("pipeline version mismatch");
        }

        prepare_idle(hal);
        configure_static_model(hal, asset);

        unsigned logit_exact = 0;
        unsigned prediction_exact = 0;
        unsigned classification_correct = 0;
        unsigned result_index_exact = 0;
        unsigned result_tag_exact = 0;
        unsigned bottom_count_exact = 0;
        unsigned interaction_count_exact = 0;

        const std::chrono::steady_clock::time_point batch_start =
            std::chrono::steady_clock::now();

        for (std::size_t index = 0;
             index < asset.samples.size();
             ++index) {
            const Sample& sample = asset.samples[index];
            const RunResult result = run_sample(hal, sample);

            const bool current_logit_exact =
                result.logit ==
                static_cast<std::int32_t>(sample.expected_logit);
            const bool current_prediction_exact =
                result.prediction == sample.expected_prediction;
            const bool current_classification_correct =
                result.prediction == sample.label;

            logit_exact += current_logit_exact ? 1u : 0u;
            prediction_exact += current_prediction_exact ? 1u : 0u;
            classification_correct +=
                current_classification_correct ? 1u : 0u;
            result_index_exact +=
                result.result_index == 0u ? 1u : 0u;
            result_tag_exact +=
                result.result_tag == EXPECTED_FINAL_TAG ? 1u : 0u;
            bottom_count_exact +=
                result.bottom_count == EXPECTED_EMBEDDING_DIM ? 1u : 0u;
            interaction_count_exact +=
                result.interaction_count ==
                EXPECTED_INTERACTION_DIM ? 1u : 0u;

            output
                << sample.sample_id << ","
                << sample.label << ","
                << sample.expected_logit << ","
                << result.logit << ","
                << sample.expected_prediction << ","
                << result.prediction << ","
                << (current_logit_exact ? 1 : 0) << ","
                << (current_prediction_exact ? 1 : 0) << ","
                << (current_classification_correct ? 1 : 0) << ","
                << result.result_index << ","
                << result.result_tag << ","
                << result.bottom_count << ","
                << result.interaction_count << "\n";

            if (!current_logit_exact ||
                !current_prediction_exact) {
                throw std::runtime_error(
                    "FPGA/reference mismatch at sample " +
                    std::to_string(sample.sample_id) +
                    ": expected_logit=" +
                    std::to_string(sample.expected_logit) +
                    " fpga_logit=" +
                    std::to_string(result.logit));
            }

            if ((index + 1u) % 32u == 0u ||
                index + 1u == asset.samples.size()) {
                std::cout
                    << "A11_BATCH_PROGRESS="
                    << (index + 1u) << "/"
                    << asset.samples.size()
                    << " LAST_SAMPLE_ID="
                    << sample.sample_id
                    << " LAST_LOGIT="
                    << result.logit << "\n";
            }
        }

        const std::chrono::steady_clock::time_point batch_end =
            std::chrono::steady_clock::now();
        const long long elapsed_us =
            std::chrono::duration_cast<std::chrono::microseconds>(
                batch_end - batch_start).count();

        output.close();
        if (!output) {
            throw std::runtime_error("failed while writing output CSV");
        }

        if (logit_exact != EXPECTED_SAMPLE_COUNT ||
            prediction_exact != EXPECTED_SAMPLE_COUNT ||
            result_index_exact != EXPECTED_SAMPLE_COUNT ||
            result_tag_exact != EXPECTED_SAMPLE_COUNT ||
            bottom_count_exact != EXPECTED_SAMPLE_COUNT ||
            interaction_count_exact != EXPECTED_SAMPLE_COUNT) {
            throw std::runtime_error(
                "one or more 256-sample exact-count checks failed");
        }
        if (classification_correct !=
            EXPECTED_CLASSIFICATION_CORRECT) {
            throw std::runtime_error(
                "classification correct-count mismatch");
        }

        std::cout
            << "PIPELINE_START_COMMANDS=256\n"
            << "FPGA_LOGIT_EXACT=256\n"
            << "FPGA_PREDICTION_EXACT=256\n"
            << "FPGA_RESULT_INDEX_EXACT=256\n"
            << "FPGA_RESULT_TAG_EXACT=256\n"
            << "FPGA_BOTTOM_COUNT_EXACT=256\n"
            << "FPGA_INTERACTION_COUNT_EXACT=256\n"
            << "FPGA_CLASSIFICATION_CORRECT="
            << classification_correct << "\n"
            << "FPGA_CLASSIFICATION_ACCURACY=0.890625\n"
            << "BATCH_ELAPSED_US=" << elapsed_us << "\n"
            << "NO_FPGA_PROGRAMMING=1\n"
            << "NO_FPGA_RESET=1\n"
            << "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_PASS "
            << "samples=256 logits=256 predictions=256 "
            << "correct=228 accuracy=0.890625 tag=4\n";

        return 0;
    } catch (const std::exception& error) {
        std::cerr
            << "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_FAILED: "
            << error.what() << "\n";
        return 1;
    }
}
