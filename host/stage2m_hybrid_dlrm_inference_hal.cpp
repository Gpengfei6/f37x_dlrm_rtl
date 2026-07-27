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
constexpr std::uint32_t STATUS_CORE_ERROR = 1u << 4;
constexpr std::uint32_t STATUS_WRAPPER_ERROR = 1u << 5;
constexpr std::uint32_t STATUS_FINAL_BUFFER = 1u << 6;
constexpr std::uint32_t STATUS_COMMAND_PENDING = 1u << 7;

constexpr std::uint32_t EXPECTED_VERSION = 0x00024701;
constexpr std::size_t NUM_PE = 16;
constexpr std::size_t MAX_LAYERS = 4;
constexpr std::size_t MAX_DIM = 1024;
constexpr std::size_t MAX_WEIGHT_VALUES = 65536;
constexpr std::size_t MAX_BIAS_VALUES = 1024;
constexpr std::uint64_t ACC_LIMIT = 1ULL << 47;

const unsigned char PACKAGE_MAGIC[8] = {
    'F', '3', '7', 'X', 'H', 'D', '1', '\0'
};
constexpr std::uint32_t PACKAGE_VERSION = 1;
constexpr std::uint32_t PACKAGE_HEADER_BYTES = 128;
constexpr std::uint32_t FLAG_LABELS = 1u << 0;
constexpr std::uint32_t FLAG_EXPECTED_BOTTOM = 1u << 1;
constexpr std::uint32_t FLAG_EXPECTED_INTERACTION = 1u << 2;
constexpr std::uint32_t FLAG_EXPECTED_LOGIT = 1u << 3;

std::string hex32(std::uint32_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(8) << std::setfill('0')
           << value;
    return stream.str();
}

std::string hex64(std::uint64_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << std::setw(16) << std::setfill('0')
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

std::uint64_t fnv1a64(
    const std::vector<unsigned char>& data,
    std::size_t begin,
    std::size_t end)
{
    std::uint64_t value = 0xCBF29CE484222325ULL;
    for (std::size_t index = begin; index < end; ++index) {
        value ^= static_cast<std::uint64_t>(data[index]);
        value *= 0x100000001B3ULL;
    }
    return value;
}

class ByteReader {
public:
    ByteReader(
        const std::vector<unsigned char>& data,
        std::size_t begin,
        std::size_t end)
        : data_(data), begin_(begin), position_(begin), end_(end)
    {
        if (begin > end || end > data.size()) {
            throw std::runtime_error("invalid package reader bounds");
        }
    }

    std::size_t remaining() const
    {
        return end_ - position_;
    }

    unsigned char read_u8()
    {
        require(1);
        return data_[position_++];
    }

    std::uint16_t read_u16()
    {
        require(2);
        const std::uint16_t value =
            static_cast<std::uint16_t>(data_[position_]) |
            (static_cast<std::uint16_t>(data_[position_ + 1]) << 8);
        position_ += 2;
        return value;
    }

    std::uint32_t read_u32()
    {
        require(4);
        std::uint32_t value = 0;
        for (unsigned int index = 0; index < 4; ++index) {
            value |= static_cast<std::uint32_t>(data_[position_ + index])
                     << (8u * index);
        }
        position_ += 4;
        return value;
    }

    std::uint64_t read_u64()
    {
        require(8);
        std::uint64_t value = 0;
        for (unsigned int index = 0; index < 8; ++index) {
            value |= static_cast<std::uint64_t>(data_[position_ + index])
                     << (8u * index);
        }
        position_ += 8;
        return value;
    }

    std::int16_t read_i16()
    {
        return static_cast<std::int16_t>(read_u16());
    }

    std::int32_t read_i32()
    {
        return static_cast<std::int32_t>(read_u32());
    }

    std::string read_string(std::size_t size)
    {
        require(size);
        const std::string result(
            reinterpret_cast<const char*>(&data_[position_]), size);
        position_ += size;
        return result;
    }

private:
    void require(std::size_t size) const
    {
        if (size > remaining()) {
            throw std::runtime_error("truncated hybrid DLRM package");
        }
    }

    const std::vector<unsigned char>& data_;
    std::size_t begin_;
    std::size_t position_;
    std::size_t end_;
};

struct ModelLayer {
    std::uint32_t in_dim;
    std::uint32_t out_dim;
    std::uint32_t output_shift;
    bool relu;
    std::uint32_t weight_base;
    std::uint32_t bias_base;
    std::uint32_t input_scale_log2;
    std::uint32_t output_scale_log2;
    std::uint32_t weight_count;
    std::uint32_t bias_count;
    std::vector<std::int8_t> weights;
    std::vector<std::int32_t> biases;
};

struct HybridSample {
    std::uint32_t sample_id;
    std::uint32_t label;
    std::vector<std::int16_t> dense_input;
    std::vector<std::uint32_t> categorical_ids;
    std::vector<std::int16_t> expected_bottom;
    std::vector<std::int16_t> expected_interaction;
    std::vector<std::int16_t> expected_logit;
};

struct HybridPackage {
    std::string name;
    std::uint32_t flags;
    std::uint32_t dense_dim;
    std::uint32_t embedding_dim;
    std::uint32_t interaction_dim;
    std::uint32_t dense_scale_log2;
    std::uint32_t vector_scale_log2;
    std::uint32_t top_hidden_scale_log2;
    std::uint32_t final_scale_log2;
    std::uint32_t interaction_shift;
    std::uint64_t payload_hash;
    std::vector<std::uint32_t> table_sizes;
    std::vector<ModelLayer> bottom_layers;
    std::vector<ModelLayer> top_layers;
    std::vector<std::vector<std::int16_t> > embeddings;
    std::vector<HybridSample> samples;
};

std::vector<unsigned char> read_binary_file(const std::string& path)
{
    std::ifstream input(path.c_str(), std::ios::binary);
    if (!input) {
        throw std::runtime_error("cannot open hybrid package: " + path);
    }
    input.seekg(0, std::ios::end);
    const std::streamoff length = input.tellg();
    if (length < 0) {
        throw std::runtime_error("cannot determine hybrid package size");
    }
    input.seekg(0, std::ios::beg);
    std::vector<unsigned char> data(static_cast<std::size_t>(length));
    if (!data.empty()) {
        input.read(
            reinterpret_cast<char*>(&data[0]),
            static_cast<std::streamsize>(data.size()));
    }
    if (!input && !data.empty()) {
        throw std::runtime_error("failed to read complete hybrid package");
    }
    return data;
}

ModelLayer read_layer_descriptor(ByteReader& reader)
{
    ModelLayer layer;
    layer.in_dim = reader.read_u32();
    layer.out_dim = reader.read_u32();
    layer.output_shift = reader.read_u32();
    const std::uint32_t relu = reader.read_u32();
    layer.weight_base = reader.read_u32();
    layer.bias_base = reader.read_u32();
    layer.input_scale_log2 = reader.read_u32();
    layer.output_scale_log2 = reader.read_u32();
    layer.weight_count = reader.read_u32();
    layer.bias_count = reader.read_u32();
    layer.relu = relu != 0;

    if (relu > 1) {
        throw std::runtime_error("invalid ReLU flag");
    }
    if (layer.in_dim < 1 || layer.in_dim > MAX_DIM ||
        layer.out_dim < 1 || layer.out_dim > MAX_DIM) {
        throw std::runtime_error("invalid layer dimension");
    }
    if (layer.output_shift > 48) {
        throw std::runtime_error("layer output shift exceeds 48");
    }
    if (layer.weight_count != layer.in_dim * layer.out_dim) {
        throw std::runtime_error("layer weight count mismatch");
    }
    if (layer.bias_count != layer.out_dim) {
        throw std::runtime_error("layer bias count mismatch");
    }
    return layer;
}

void validate_layer_chain(
    const std::vector<ModelLayer>& layers,
    std::uint32_t expected_input,
    std::uint32_t expected_output,
    const char* name)
{
    if (layers.empty() || layers.size() > MAX_LAYERS) {
        throw std::runtime_error(std::string(name) + " layer count invalid");
    }
    std::uint32_t current = expected_input;
    for (std::size_t index = 0; index < layers.size(); ++index) {
        if (layers[index].in_dim != current) {
            throw std::runtime_error(
                std::string(name) + " dimensions are discontinuous");
        }
        current = layers[index].out_dim;
    }
    if (current != expected_output) {
        throw std::runtime_error(
            std::string(name) + " final dimension mismatch");
    }
}

HybridPackage load_hybrid_package(const std::string& path)
{
    const std::vector<unsigned char> data = read_binary_file(path);
    if (data.size() < PACKAGE_HEADER_BYTES) {
        throw std::runtime_error("hybrid package smaller than header");
    }

    ByteReader header(data, 0, PACKAGE_HEADER_BYTES);
    for (std::size_t index = 0; index < sizeof(PACKAGE_MAGIC); ++index) {
        if (header.read_u8() != PACKAGE_MAGIC[index]) {
            throw std::runtime_error("hybrid package magic mismatch");
        }
    }

    const std::uint32_t version = header.read_u32();
    const std::uint32_t header_bytes = header.read_u32();
    const std::uint32_t flags = header.read_u32();
    const std::uint32_t sample_count = header.read_u32();
    const std::uint32_t num_tables = header.read_u32();
    const std::uint32_t dense_dim = header.read_u32();
    const std::uint32_t embedding_dim = header.read_u32();
    const std::uint32_t interaction_dim = header.read_u32();
    const std::uint32_t bottom_layer_count = header.read_u32();
    const std::uint32_t top_layer_count = header.read_u32();
    const std::uint32_t bottom_weight_count = header.read_u32();
    const std::uint32_t bottom_bias_count = header.read_u32();
    const std::uint32_t top_weight_count = header.read_u32();
    const std::uint32_t top_bias_count = header.read_u32();
    const std::uint32_t embedding_value_count = header.read_u32();
    const std::uint32_t dense_scale_log2 = header.read_u32();
    const std::uint32_t vector_scale_log2 = header.read_u32();
    const std::uint32_t top_hidden_scale_log2 = header.read_u32();
    const std::uint32_t final_scale_log2 = header.read_u32();
    const std::uint32_t interaction_shift = header.read_u32();
    const std::uint64_t payload_bytes = header.read_u64();
    const std::uint64_t expected_payload_hash = header.read_u64();
    const std::uint64_t reserved0 = header.read_u64();
    const std::uint64_t reserved1 = header.read_u64();
    const std::uint64_t reserved2 = header.read_u64();

    if (version != PACKAGE_VERSION ||
        header_bytes != PACKAGE_HEADER_BYTES) {
        throw std::runtime_error("unsupported hybrid package header");
    }
    if (reserved0 != 0 || reserved1 != 0 || reserved2 != 0) {
        throw std::runtime_error("hybrid package reserved field is nonzero");
    }
    const std::uint32_t required_flags =
        FLAG_LABELS |
        FLAG_EXPECTED_BOTTOM |
        FLAG_EXPECTED_INTERACTION |
        FLAG_EXPECTED_LOGIT;
    if ((flags & required_flags) != required_flags) {
        throw std::runtime_error("hybrid package required flags missing");
    }
    if (sample_count < 1 || num_tables < 1 ||
        dense_dim < 1 || embedding_dim < 1 ||
        interaction_dim < 1) {
        throw std::runtime_error("hybrid package dimension/count is zero");
    }
    if (bottom_layer_count < 1 || bottom_layer_count > MAX_LAYERS ||
        top_layer_count < 1 || top_layer_count > MAX_LAYERS) {
        throw std::runtime_error("hybrid package layer count invalid");
    }
    if (payload_bytes != data.size() - PACKAGE_HEADER_BYTES) {
        throw std::runtime_error("hybrid package payload length mismatch");
    }

    const std::uint64_t observed_payload_hash = fnv1a64(
        data, PACKAGE_HEADER_BYTES, data.size());
    if (observed_payload_hash != expected_payload_hash) {
        throw std::runtime_error(
            "hybrid payload FNV1a64 mismatch: expected " +
            hex64(expected_payload_hash) + ", got " +
            hex64(observed_payload_hash));
    }

    ByteReader payload(data, PACKAGE_HEADER_BYTES, data.size());
    const std::uint32_t name_bytes = payload.read_u32();
    if (name_bytes < 1 || name_bytes > 4096) {
        throw std::runtime_error("hybrid package name length invalid");
    }

    HybridPackage package;
    package.name = payload.read_string(name_bytes);
    package.flags = flags;
    package.dense_dim = dense_dim;
    package.embedding_dim = embedding_dim;
    package.interaction_dim = interaction_dim;
    package.dense_scale_log2 = dense_scale_log2;
    package.vector_scale_log2 = vector_scale_log2;
    package.top_hidden_scale_log2 = top_hidden_scale_log2;
    package.final_scale_log2 = final_scale_log2;
    package.interaction_shift = interaction_shift;
    package.payload_hash = observed_payload_hash;

    package.table_sizes.reserve(num_tables);
    std::uint64_t observed_embedding_values = 0;
    for (std::uint32_t index = 0; index < num_tables; ++index) {
        const std::uint32_t table_size = payload.read_u32();
        if (table_size < 1) {
            throw std::runtime_error("embedding table size is zero");
        }
        package.table_sizes.push_back(table_size);
        observed_embedding_values +=
            static_cast<std::uint64_t>(table_size) * embedding_dim;
    }
    if (observed_embedding_values != embedding_value_count) {
        throw std::runtime_error("embedding value count mismatch");
    }

    package.bottom_layers.reserve(bottom_layer_count);
    for (std::uint32_t index = 0; index < bottom_layer_count; ++index) {
        package.bottom_layers.push_back(read_layer_descriptor(payload));
    }
    package.top_layers.reserve(top_layer_count);
    for (std::uint32_t index = 0; index < top_layer_count; ++index) {
        package.top_layers.push_back(read_layer_descriptor(payload));
    }

    const std::uint32_t expected_interaction_dim =
        embedding_dim +
        (num_tables + 1u) * num_tables / 2u;
    if (interaction_dim != expected_interaction_dim) {
        throw std::runtime_error("interaction dimension contract mismatch");
    }
    validate_layer_chain(
        package.bottom_layers, dense_dim, embedding_dim, "bottom MLP");
    validate_layer_chain(
        package.top_layers, interaction_dim, 1, "top MLP");

    std::uint64_t expected_weight_base = 0;
    std::uint64_t expected_bias_base = 0;
    std::uint64_t observed_bottom_weights = 0;
    std::uint64_t observed_bottom_biases = 0;
    std::uint64_t observed_top_weights = 0;
    std::uint64_t observed_top_biases = 0;

    for (std::size_t index = 0;
         index < package.bottom_layers.size();
         ++index) {
        ModelLayer& layer = package.bottom_layers[index];
        if (layer.weight_base != expected_weight_base ||
            layer.bias_base != expected_bias_base) {
            throw std::runtime_error("bottom parameter base mismatch");
        }
        expected_weight_base += layer.weight_count;
        expected_bias_base += layer.bias_count;
        observed_bottom_weights += layer.weight_count;
        observed_bottom_biases += layer.bias_count;
    }
    for (std::size_t index = 0;
         index < package.top_layers.size();
         ++index) {
        ModelLayer& layer = package.top_layers[index];
        if (layer.weight_base != expected_weight_base ||
            layer.bias_base != expected_bias_base) {
            throw std::runtime_error("top parameter base mismatch");
        }
        expected_weight_base += layer.weight_count;
        expected_bias_base += layer.bias_count;
        observed_top_weights += layer.weight_count;
        observed_top_biases += layer.bias_count;
    }

    if (observed_bottom_weights != bottom_weight_count ||
        observed_bottom_biases != bottom_bias_count ||
        observed_top_weights != top_weight_count ||
        observed_top_biases != top_bias_count) {
        throw std::runtime_error("header parameter count mismatch");
    }
    if (expected_weight_base > MAX_WEIGHT_VALUES ||
        expected_bias_base > MAX_BIAS_VALUES) {
        throw std::runtime_error("hybrid package exceeds hardware memory");
    }

    for (std::size_t layer_index = 0;
         layer_index < package.bottom_layers.size();
         ++layer_index) {
        ModelLayer& layer = package.bottom_layers[layer_index];
        layer.weights.reserve(layer.weight_count);
        for (std::uint32_t index = 0; index < layer.weight_count; ++index) {
            layer.weights.push_back(
                static_cast<std::int8_t>(payload.read_u8()));
        }
    }
    for (std::size_t layer_index = 0;
         layer_index < package.bottom_layers.size();
         ++layer_index) {
        ModelLayer& layer = package.bottom_layers[layer_index];
        layer.biases.reserve(layer.bias_count);
        for (std::uint32_t index = 0; index < layer.bias_count; ++index) {
            const std::int32_t value = payload.read_i32();
            if (value < -8388608 || value > 8388607) {
                throw std::runtime_error("bottom bias exceeds INT24");
            }
            layer.biases.push_back(value);
        }
    }
    for (std::size_t layer_index = 0;
         layer_index < package.top_layers.size();
         ++layer_index) {
        ModelLayer& layer = package.top_layers[layer_index];
        layer.weights.reserve(layer.weight_count);
        for (std::uint32_t index = 0; index < layer.weight_count; ++index) {
            layer.weights.push_back(
                static_cast<std::int8_t>(payload.read_u8()));
        }
    }
    for (std::size_t layer_index = 0;
         layer_index < package.top_layers.size();
         ++layer_index) {
        ModelLayer& layer = package.top_layers[layer_index];
        layer.biases.reserve(layer.bias_count);
        for (std::uint32_t index = 0; index < layer.bias_count; ++index) {
            const std::int32_t value = payload.read_i32();
            if (value < -8388608 || value > 8388607) {
                throw std::runtime_error("top bias exceeds INT24");
            }
            layer.biases.push_back(value);
        }
    }

    package.embeddings.reserve(num_tables);
    for (std::uint32_t table_index = 0;
         table_index < num_tables;
         ++table_index) {
        const std::size_t value_count =
            static_cast<std::size_t>(package.table_sizes[table_index]) *
            embedding_dim;
        std::vector<std::int16_t> table;
        table.reserve(value_count);
        for (std::size_t index = 0; index < value_count; ++index) {
            table.push_back(payload.read_i16());
        }
        package.embeddings.push_back(table);
    }

    package.samples.reserve(sample_count);
    for (std::uint32_t sample_index = 0;
         sample_index < sample_count;
         ++sample_index) {
        HybridSample sample;
        sample.sample_id = payload.read_u32();
        sample.label = payload.read_u32();
        if (sample.sample_id != sample_index || sample.label > 1) {
            throw std::runtime_error("hybrid sample metadata invalid");
        }

        sample.dense_input.reserve(dense_dim);
        for (std::uint32_t index = 0; index < dense_dim; ++index) {
            sample.dense_input.push_back(payload.read_i16());
        }

        sample.categorical_ids.reserve(num_tables);
        for (std::uint32_t table_index = 0;
             table_index < num_tables;
             ++table_index) {
            const std::uint32_t id = payload.read_u32();
            if (id >= package.table_sizes[table_index]) {
                throw std::runtime_error("categorical ID outside table");
            }
            sample.categorical_ids.push_back(id);
        }

        sample.expected_bottom.reserve(embedding_dim);
        for (std::uint32_t index = 0; index < embedding_dim; ++index) {
            sample.expected_bottom.push_back(payload.read_i16());
        }

        sample.expected_interaction.reserve(interaction_dim);
        for (std::uint32_t index = 0; index < interaction_dim; ++index) {
            sample.expected_interaction.push_back(payload.read_i16());
        }

        sample.expected_logit.push_back(payload.read_i16());
        package.samples.push_back(sample);
    }

    if (payload.remaining() != 0) {
        throw std::runtime_error("hybrid package contains trailing bytes");
    }
    return package;
}

std::int16_t quantize_accumulator(
    std::int64_t accumulator,
    std::uint32_t shift,
    bool relu)
{
    if (accumulator <= -static_cast<std::int64_t>(ACC_LIMIT) ||
        accumulator >= static_cast<std::int64_t>(ACC_LIMIT)) {
        throw std::runtime_error("signed 48-bit accumulator exceeded");
    }

    std::int64_t shifted = accumulator;
    if (shift != 0) {
        const std::uint64_t magnitude = accumulator < 0
            ? static_cast<std::uint64_t>(-accumulator)
            : static_cast<std::uint64_t>(accumulator);
        const std::uint64_t rounded =
            (magnitude + (1ULL << (shift - 1u))) >> shift;
        shifted = accumulator < 0
            ? -static_cast<std::int64_t>(rounded)
            : static_cast<std::int64_t>(rounded);
    }

    if (shifted > std::numeric_limits<std::int16_t>::max()) {
        shifted = std::numeric_limits<std::int16_t>::max();
    }
    if (shifted < std::numeric_limits<std::int16_t>::min()) {
        shifted = std::numeric_limits<std::int16_t>::min();
    }
    if (relu && shifted < 0) {
        shifted = 0;
    }
    return static_cast<std::int16_t>(shifted);
}

std::vector<std::int16_t> software_mlp(
    const std::vector<ModelLayer>& layers,
    const std::vector<std::int16_t>& input)
{
    std::vector<std::int16_t> activations = input;
    for (std::size_t layer_index = 0;
         layer_index < layers.size();
         ++layer_index) {
        const ModelLayer& layer = layers[layer_index];
        if (activations.size() != layer.in_dim) {
            throw std::runtime_error(
                "software MLP activation dimension mismatch");
        }

        std::vector<std::int16_t> outputs;
        outputs.reserve(layer.out_dim);
        for (std::uint32_t output_index = 0;
             output_index < layer.out_dim;
             ++output_index) {
            std::int64_t accumulator = layer.biases[output_index];
            for (std::uint32_t input_index = 0;
                 input_index < layer.in_dim;
                 ++input_index) {
                const std::size_t weight_index =
                    static_cast<std::size_t>(output_index) * layer.in_dim +
                    input_index;
                accumulator +=
                    static_cast<std::int64_t>(activations[input_index]) *
                    static_cast<std::int64_t>(
                        layer.weights[weight_index]);
            }
            outputs.push_back(quantize_accumulator(
                accumulator, layer.output_shift, layer.relu));
        }
        activations = outputs;
    }
    return activations;
}

std::vector<std::int16_t> cpu_interaction(
    const HybridPackage& package,
    const std::vector<std::int16_t>& bottom,
    const std::vector<std::uint32_t>& categorical_ids)
{
    if (bottom.size() != package.embedding_dim ||
        categorical_ids.size() != package.table_sizes.size()) {
        throw std::runtime_error("CPU interaction input dimension mismatch");
    }

    std::vector<std::vector<std::int16_t> > vectors;
    vectors.push_back(bottom);

    for (std::size_t table_index = 0;
         table_index < package.table_sizes.size();
         ++table_index) {
        const std::uint32_t id = categorical_ids[table_index];
        const std::size_t offset =
            static_cast<std::size_t>(id) * package.embedding_dim;
        std::vector<std::int16_t> vector;
        vector.reserve(package.embedding_dim);
        for (std::uint32_t index = 0;
             index < package.embedding_dim;
             ++index) {
            vector.push_back(
                package.embeddings[table_index][offset + index]);
        }
        vectors.push_back(vector);
    }

    std::vector<std::int16_t> result = bottom;
    for (std::size_t row = 0; row < vectors.size(); ++row) {
        for (std::size_t column = 0; column < row; ++column) {
            std::int64_t accumulator = 0;
            for (std::uint32_t index = 0;
                 index < package.embedding_dim;
                 ++index) {
                accumulator +=
                    static_cast<std::int64_t>(vectors[row][index]) *
                    static_cast<std::int64_t>(vectors[column][index]);
            }
            result.push_back(quantize_accumulator(
                accumulator, package.interaction_shift, false));
        }
    }

    if (result.size() != package.interaction_dim) {
        throw std::runtime_error("CPU interaction output dimension mismatch");
    }
    return result;
}

std::string vector_text(const std::vector<std::int16_t>& values)
{
    std::ostringstream stream;
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index != 0) {
            stream << ':';
        }
        stream << values[index];
    }
    return stream.str();
}

struct PackageVerification {
    std::uint64_t bottom_exact;
    std::uint64_t interaction_exact;
    std::uint64_t top_exact;
    std::uint64_t classification_correct;
};

PackageVerification verify_package_reference(
    const HybridPackage& package)
{
    PackageVerification result = {};
    for (std::size_t sample_index = 0;
         sample_index < package.samples.size();
         ++sample_index) {
        const HybridSample& sample = package.samples[sample_index];
        const std::vector<std::int16_t> bottom =
            software_mlp(package.bottom_layers, sample.dense_input);
        if (bottom != sample.expected_bottom) {
            throw std::runtime_error(
                "package bottom reference mismatch at sample " +
                std::to_string(sample.sample_id));
        }
        ++result.bottom_exact;

        const std::vector<std::int16_t> interaction =
            cpu_interaction(
                package, bottom, sample.categorical_ids);
        if (interaction != sample.expected_interaction) {
            throw std::runtime_error(
                "package interaction reference mismatch at sample " +
                std::to_string(sample.sample_id));
        }
        ++result.interaction_exact;

        const std::vector<std::int16_t> logit =
            software_mlp(package.top_layers, interaction);
        if (logit != sample.expected_logit) {
            throw std::runtime_error(
                "package top reference mismatch at sample " +
                std::to_string(sample.sample_id));
        }
        ++result.top_exact;

        const std::uint32_t prediction = logit[0] >= 0 ? 1u : 0u;
        if (prediction == sample.label) {
            ++result.classification_correct;
        }
    }
    return result;
}

struct DescriptorWords {
    std::uint32_t word0;
    std::uint32_t word1;
    std::uint32_t word2;
};

DescriptorWords pack_descriptor(const ModelLayer& layer)
{
    __uint128_t value = 0;
    value |= static_cast<__uint128_t>(layer.in_dim & 0x7FFu);
    value |= static_cast<__uint128_t>(layer.out_dim & 0x7FFu) << 11;
    value |= static_cast<__uint128_t>(layer.weight_base) << 22;
    value |= static_cast<__uint128_t>(layer.bias_base) << 54;
    value |= static_cast<__uint128_t>(layer.output_shift & 0x3Fu) << 86;
    value |= static_cast<__uint128_t>(layer.relu ? 1u : 0u) << 92;

    DescriptorWords result;
    result.word0 = static_cast<std::uint32_t>(value);
    result.word1 = static_cast<std::uint32_t>(value >> 32);
    result.word2 = static_cast<std::uint32_t>(value >> 64);
    return result;
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
            throw std::runtime_error("xclIPName2Index failed");
        }
        ip_index_ = static_cast<unsigned int>(detected_index);

        std::cout << "HAL_DEVICE_INDEX=" << kDeviceIndex << "\n"
                  << "HAL_TARGET_BDF=" << kTargetBdf << "\n"
                  << "HAL_XCLBIN_UUID=" << uuid_to_string(uuid_) << "\n"
                  << "HAL_IP_NAME=" << kIpName << "\n"
                  << "HAL_IP_INDEX=" << ip_index_ << "\n";

        if (ip_index_ != kExpectedIpIndex) {
            throw std::runtime_error("unexpected IP index");
        }

        const int context_rc =
            xclOpenContext(handle_, uuid_, ip_index_, false);
        if (context_rc != 0) {
            throw std::runtime_error(
                "xclOpenContext(exclusive) failed: rc=" +
                std::to_string(context_rc));
        }
        context_open_ = true;
        std::cout << "HAL_EXCLUSIVE_CONTEXT_OPEN=1\n";
    }

    ~HalSession()
    {
        if (context_open_) {
            const int rc = xclCloseContext(handle_, uuid_, ip_index_);
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
        const int rc = xclRegWrite(handle_, ip_index_, offset, value);
        if (rc != 0) {
            throw std::runtime_error(
                "xclRegWrite failed at " + hex32(offset) +
                " value=" + hex32(value) +
                " rc=" + std::to_string(rc));
        }
    }

    std::uint32_t read(std::uint32_t offset)
    {
        std::uint32_t value = 0;
        const int rc = xclRegRead(handle_, ip_index_, offset, &value);
        if (rc != 0) {
            throw std::runtime_error(
                "xclRegRead failed at " + hex32(offset) +
                " rc=" + std::to_string(rc));
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

    throw std::runtime_error(
        std::string("timeout while ") + description +
        "; last status=" + hex32(status));
}

void recover_safe_stale_error(HalSession& session)
{
    const std::uint32_t status = session.read(ADDR_CONTROL_STATUS);
    if ((status & (STATUS_CORE_ERROR | STATUS_WRAPPER_ERROR)) == 0) {
        return;
    }

    const std::uint32_t core_error_code = (status >> 24) & 0xFu;
    const std::uint32_t wrapper_error_code = (status >> 28) & 0xFu;
    const bool no_result = (status & STATUS_RESULT_VALID) == 0;
    const bool no_pending = (status & STATUS_COMMAND_PENDING) == 0;

    if (core_error_code >= 1 && core_error_code <= 7 &&
        wrapper_error_code == 0 && no_result && no_pending) {
        std::cout << "RECOVERING_STALE_CORE_ERROR status=" << hex32(status)
                  << " core_error_code=" << core_error_code << "\n";
        session.write(ADDR_CONTROL_STATUS, CMD_ERROR_ACK);
        const auto deadline =
            std::chrono::steady_clock::now() +
            std::chrono::milliseconds(1000);
        while (std::chrono::steady_clock::now() < deadline) {
            const std::uint32_t current =
                session.read(ADDR_CONTROL_STATUS);
            if ((current & (STATUS_CORE_ERROR |
                            STATUS_WRAPPER_ERROR |
                            STATUS_COMMAND_PENDING |
                            STATUS_RESULT_VALID)) == 0 &&
                (current & STATUS_BUSY) == 0) {
                std::cout << "STALE_CORE_ERROR_ACKNOWLEDGED status="
                          << hex32(current) << "\n";
                return;
            }
            std::this_thread::sleep_for(
                std::chrono::microseconds(25));
        }
        throw std::runtime_error(
            "timeout acknowledging stale core error");
    }

    throw_on_error_status(status, "initial status check");
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

void wait_result_count(HalSession& session, std::uint32_t expected_count)
{
    const auto deadline =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(2000);
    std::uint32_t count = 0;

    while (std::chrono::steady_clock::now() < deadline) {
        const std::uint32_t status =
            session.read(ADDR_CONTROL_STATUS);
        throw_on_error_status(status, "waiting for result count");
        count = session.read(ADDR_RESULT_COUNT);
        if (count == expected_count) {
            return;
        }
        if (count > expected_count) {
            throw std::runtime_error(
                "result count advanced unexpectedly");
        }
        std::this_thread::sleep_for(std::chrono::microseconds(25));
    }

    throw std::runtime_error(
        "timeout waiting for result count " +
        std::to_string(expected_count) +
        "; last count=" + std::to_string(count));
}

void prepare_clean_inference(HalSession& session)
{
    const std::uint32_t status =
        session.read(ADDR_CONTROL_STATUS);
    throw_on_error_status(status, "pre-inference status check");
    if ((status & (STATUS_BUSY |
                   STATUS_COMMAND_PENDING |
                   STATUS_RESULT_VALID)) != 0) {
        throw std::runtime_error(
            "kernel is not clean before inference: status=" +
            hex32(status));
    }

    session.write(ADDR_CONTROL_STATUS, CMD_CLEAR_DONE);
    poll_status(
        session,
        [](std::uint32_t current) {
            return (current & STATUS_DONE) == 0;
        },
        "clearing done before inference",
        std::chrono::milliseconds(1000));
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
        throw std::runtime_error("bias exceeds signed INT24");
    }
    session.write(ADDR_BIAS_ADDRESS, address);
    session.write(
        ADDR_BIAS_DATA,
        static_cast<std::uint32_t>(value) & 0x00FFFFFFu);
    session.write(ADDR_CONTROL_STATUS, CMD_BIAS_COMMIT);
    wait_command_idle(session, "waiting for bias commit");
}

void write_activation_vector(
    HalSession& session,
    const std::vector<std::int16_t>& values,
    std::uint32_t buffer_select)
{
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
        wait_command_idle(session, "waiting for activation commit");
    }
}

double load_parameters(
    HalSession& session,
    const HybridPackage& package)
{
    const auto begin = std::chrono::steady_clock::now();

    const std::vector<ModelLayer>* phases[2] = {
        &package.bottom_layers, &package.top_layers
    };
    for (int phase = 0; phase < 2; ++phase) {
        const std::vector<ModelLayer>& layers = *phases[phase];
        for (std::size_t layer_index = 0;
             layer_index < layers.size();
             ++layer_index) {
            const ModelLayer& layer = layers[layer_index];
            for (std::size_t index = 0;
                 index < layer.weights.size();
                 ++index) {
                write_weight(
                    session,
                    layer.weight_base +
                    static_cast<std::uint32_t>(index),
                    layer.weights[index]);
            }
            for (std::size_t index = 0;
                 index < layer.biases.size();
                 ++index) {
                write_bias(
                    session,
                    layer.bias_base +
                    static_cast<std::uint32_t>(index),
                    layer.biases[index]);
            }
        }
    }

    const auto end = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::micro>(
        end - begin).count();
}

double program_descriptors(
    HalSession& session,
    const std::vector<ModelLayer>& layers)
{
    const auto begin = std::chrono::steady_clock::now();
    for (std::size_t index = 0; index < layers.size(); ++index) {
        write_descriptor(
            session,
            static_cast<std::uint32_t>(index),
            pack_descriptor(layers[index]));
    }
    const auto end = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::micro>(
        end - begin).count();
}

struct InferenceObservation {
    std::vector<std::int16_t> outputs;
    std::uint32_t final_status;
    std::uint32_t result_count;
    double first_result_latency_us;
    double final_result_latency_us;
};

InferenceObservation run_network(
    HalSession& session,
    const std::vector<ModelLayer>& layers,
    const std::vector<std::int16_t>& input)
{
    if (layers.empty()) {
        throw std::runtime_error("cannot run empty layer chain");
    }

    prepare_clean_inference(session);
    write_activation_vector(session, input, 0);
    session.write(
        ADDR_LAYER_COUNT,
        static_cast<std::uint32_t>(layers.size()));
    session.write(ADDR_INITIAL_BUFFER, 0);

    const auto start = std::chrono::steady_clock::now();
    session.write(ADDR_CONTROL_STATUS, CMD_START);
    wait_command_idle(session, "waiting for network start acceptance");

    InferenceObservation observation;
    observation.first_result_latency_us = 0.0;
    observation.final_result_latency_us = 0.0;

    const std::uint32_t output_dim = layers.back().out_dim;
    const std::uint32_t expected_tag =
        static_cast<std::uint32_t>(layers.size() - 1u);
    const bool expected_final_buffer =
        (layers.size() & 1u) != 0u;

    for (std::uint32_t expected_index = 0;
         expected_index < output_dim;
         ++expected_index) {
        const std::uint32_t status = poll_status(
            session,
            [](std::uint32_t current) {
                return (current & STATUS_RESULT_VALID) != 0;
            },
            "waiting for network output",
            std::chrono::milliseconds(5000));

        const auto now = std::chrono::steady_clock::now();
        const double latency_us =
            std::chrono::duration<double, std::micro>(
                now - start).count();
        if (expected_index == 0) {
            observation.first_result_latency_us = latency_us;
        }
        observation.final_result_latency_us = latency_us;

        const std::int32_t raw_value =
            static_cast<std::int32_t>(
                session.read(ADDR_RESULT_DATA));
        const std::uint32_t observed_index =
            session.read(ADDR_RESULT_INDEX) & 0x3FFu;
        const std::uint32_t meta =
            session.read(ADDR_RESULT_META);
        const std::uint32_t tag = (meta >> 8) & 0xFFu;
        const bool observed_last = (meta & 0x2u) != 0u;
        const bool expected_last =
            expected_index + 1u == output_dim;
        const bool observed_final_buffer =
            (status & STATUS_FINAL_BUFFER) != 0u;

        session.write(ADDR_CONTROL_STATUS, CMD_RESULT_POP);
        wait_result_count(session, expected_index + 1u);

        if (observed_index != expected_index) {
            throw std::runtime_error("network output index mismatch");
        }
        if (raw_value < -32768 || raw_value > 32767) {
            throw std::runtime_error(
                "network output is not sign-extended INT16");
        }
        if ((meta & 0x1u) == 0u) {
            throw std::runtime_error(
                "network output valid metadata bit missing");
        }
        if (observed_last != expected_last) {
            throw std::runtime_error(
                "network output last metadata mismatch");
        }
        if (tag != expected_tag) {
            throw std::runtime_error(
                "network output layer tag mismatch");
        }
        if (observed_final_buffer != expected_final_buffer) {
            throw std::runtime_error(
                "network final buffer status mismatch");
        }
        observation.outputs.push_back(
            static_cast<std::int16_t>(raw_value));
    }

    observation.final_status = poll_status(
        session,
        [](std::uint32_t status) {
            return (status & STATUS_DONE) != 0 &&
                   (status & STATUS_RESULT_VALID) == 0 &&
                   (status & STATUS_BUSY) == 0;
        },
        "waiting for network completion",
        std::chrono::milliseconds(5000));
    observation.result_count = session.read(ADDR_RESULT_COUNT);

    if (observation.result_count != output_dim) {
        throw std::runtime_error("network result count mismatch");
    }
    const bool final_status_buffer =
        (observation.final_status & STATUS_FINAL_BUFFER) != 0u;
    if (final_status_buffer != expected_final_buffer) {
        throw std::runtime_error(
            "network final completion buffer mismatch");
    }
    return observation;
}

void print_package_summary(
    const HybridPackage& package,
    const PackageVerification& verification)
{
    std::uint64_t bottom_weights = 0;
    std::uint64_t bottom_biases = 0;
    std::uint64_t top_weights = 0;
    std::uint64_t top_biases = 0;
    std::uint64_t embedding_values = 0;

    for (std::size_t index = 0;
         index < package.bottom_layers.size();
         ++index) {
        bottom_weights += package.bottom_layers[index].weights.size();
        bottom_biases += package.bottom_layers[index].biases.size();
    }
    for (std::size_t index = 0;
         index < package.top_layers.size();
         ++index) {
        top_weights += package.top_layers[index].weights.size();
        top_biases += package.top_layers[index].biases.size();
    }
    for (std::size_t index = 0;
         index < package.embeddings.size();
         ++index) {
        embedding_values += package.embeddings[index].size();
    }

    const double accuracy =
        static_cast<double>(verification.classification_correct) /
        static_cast<double>(package.samples.size());

    std::cout
        << "MODEL_NAME=" << package.name << "\n"
        << "BOTTOM_LAYERS=" << package.bottom_layers.size() << "\n"
        << "TOP_LAYERS=" << package.top_layers.size() << "\n"
        << "DENSE_DIM=" << package.dense_dim << "\n"
        << "EMBEDDING_TABLES=" << package.table_sizes.size() << "\n"
        << "EMBEDDING_DIM=" << package.embedding_dim << "\n"
        << "INTERACTION_DIM=" << package.interaction_dim << "\n"
        << "MODEL_SAMPLES=" << package.samples.size() << "\n"
        << "BOTTOM_WEIGHT_VALUES=" << bottom_weights << "\n"
        << "BOTTOM_BIAS_VALUES=" << bottom_biases << "\n"
        << "TOP_WEIGHT_VALUES=" << top_weights << "\n"
        << "TOP_BIAS_VALUES=" << top_biases << "\n"
        << "EMBEDDING_VALUES=" << embedding_values << "\n"
        << "MODEL_PAYLOAD_FNV1A64=" << hex64(package.payload_hash) << "\n"
        << "SOFTWARE_BOTTOM_EXACT=" << verification.bottom_exact << "\n"
        << "SOFTWARE_INTERACTION_EXACT="
        << verification.interaction_exact << "\n"
        << "SOFTWARE_TOP_EXACT=" << verification.top_exact << "\n"
        << "SOFTWARE_CLASSIFICATION_CORRECT="
        << verification.classification_correct << "\n"
        << "SOFTWARE_CLASSIFICATION_ACCURACY="
        << std::fixed << std::setprecision(6) << accuracy << "\n";

    for (std::size_t index = 0;
         index < package.bottom_layers.size();
         ++index) {
        const ModelLayer& layer = package.bottom_layers[index];
        std::cout << "BOTTOM_LAYER index=" << index
                  << " in_dim=" << layer.in_dim
                  << " out_dim=" << layer.out_dim
                  << " shift=" << layer.output_shift
                  << " relu=" << (layer.relu ? 1 : 0)
                  << " weight_base=" << layer.weight_base
                  << " bias_base=" << layer.bias_base << "\n";
    }
    for (std::size_t index = 0;
         index < package.top_layers.size();
         ++index) {
        const ModelLayer& layer = package.top_layers[index];
        std::cout << "TOP_LAYER index=" << index
                  << " in_dim=" << layer.in_dim
                  << " out_dim=" << layer.out_dim
                  << " shift=" << layer.output_shift
                  << " relu=" << (layer.relu ? 1 : 0)
                  << " weight_base=" << layer.weight_base
                  << " bias_base=" << layer.bias_base << "\n";
    }
}

struct LatencyStats {
    double first_sum;
    double final_sum;
    double first_min;
    double first_max;
    double final_min;
    double final_max;
    std::uint64_t count;

    LatencyStats()
        : first_sum(0.0),
          final_sum(0.0),
          first_min(0.0),
          first_max(0.0),
          final_min(0.0),
          final_max(0.0),
          count(0)
    {
    }

    void add(const InferenceObservation& observation)
    {
        ++count;
        first_sum += observation.first_result_latency_us;
        final_sum += observation.final_result_latency_us;
        if (count == 1 ||
            observation.first_result_latency_us < first_min) {
            first_min = observation.first_result_latency_us;
        }
        if (count == 1 ||
            observation.first_result_latency_us > first_max) {
            first_max = observation.first_result_latency_us;
        }
        if (count == 1 ||
            observation.final_result_latency_us < final_min) {
            final_min = observation.final_result_latency_us;
        }
        if (count == 1 ||
            observation.final_result_latency_us > final_max) {
            final_max = observation.final_result_latency_us;
        }
    }
};

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc == 3 && std::string(argv[1]) == "--verify-only") {
            const HybridPackage package =
                load_hybrid_package(argv[2]);
            const PackageVerification verification =
                verify_package_reference(package);
            print_package_summary(package, verification);
            std::cout << "STAGE2M_HYBRID_PACKAGE_VERIFY_PASS\n";
            return EXIT_SUCCESS;
        }

        if (argc < 3 || argc > 4) {
            std::cerr
                << "Usage:\n  " << argv[0]
                << " --verify-only <hybrid.f37xhd>\n  "
                << argv[0]
                << " <hybrid.f37xhd> <results.csv> [passes]\n";
            return EXIT_FAILURE;
        }

        const std::string package_path = argv[1];
        const std::string csv_path = argv[2];
        unsigned int passes = 1;
        if (argc == 4) {
            const unsigned long parsed =
                std::strtoul(argv[3], nullptr, 10);
            if (parsed < 1 || parsed > 100) {
                throw std::runtime_error("passes must be in 1..100");
            }
            passes = static_cast<unsigned int>(parsed);
        }

        const HybridPackage package =
            load_hybrid_package(package_path);
        const PackageVerification verification =
            verify_package_reference(package);
        print_package_summary(package, verification);

        std::cout << "STAGE2M_PASSES=" << passes << "\n"
                  << "CSV=" << csv_path << "\n";

        HalSession session;
        const std::uint32_t version = session.read(ADDR_VERSION);
        const std::uint32_t initial_status =
            session.read(ADDR_CONTROL_STATUS);
        std::cout << "VERSION=" << hex32(version) << "\n"
                  << "INITIAL_STATUS=" << hex32(initial_status) << "\n";
        if (version != EXPECTED_VERSION) {
            throw std::runtime_error("wrapper version mismatch");
        }
        recover_safe_stale_error(session);

        const double parameter_load_us =
            load_parameters(session, package);
        std::cout << "PARAMETER_LOAD_TIME_US="
                  << std::fixed << std::setprecision(3)
                  << parameter_load_us << "\n";

        std::ofstream csv(csv_path.c_str());
        if (!csv) {
            throw std::runtime_error(
                "cannot open CSV output: " + csv_path);
        }
        csv
            << "pass_index,sample_index,label,prediction,"
            << "bottom_exact,interaction_exact,top_exact,"
            << "classification_correct,bottom_expected,bottom_observed,"
            << "interaction_expected,interaction_observed,"
            << "logit_expected,logit_observed,"
            << "bottom_first_latency_us,bottom_final_latency_us,"
            << "top_first_latency_us,top_final_latency_us,status\n";

        std::uint64_t total_hybrid_inferences = 0;
        std::uint64_t total_fpga_network_runs = 0;
        std::uint64_t total_fpga_output_values = 0;
        std::uint64_t total_cpu_interactions = 0;
        std::uint64_t exact_hybrid_inferences = 0;
        std::uint64_t classification_correct = 0;
        double bottom_descriptor_us = 0.0;
        double top_descriptor_us = 0.0;
        LatencyStats bottom_latency;
        LatencyStats top_latency;

        for (unsigned int pass_index = 0;
             pass_index < passes;
             ++pass_index) {
            bottom_descriptor_us +=
                program_descriptors(session, package.bottom_layers);

            std::vector<std::vector<std::int16_t> > observed_bottom;
            std::vector<InferenceObservation> bottom_observations;
            observed_bottom.reserve(package.samples.size());
            bottom_observations.reserve(package.samples.size());

            for (std::size_t sample_index = 0;
                 sample_index < package.samples.size();
                 ++sample_index) {
                const HybridSample& sample =
                    package.samples[sample_index];
                const InferenceObservation observation =
                    run_network(
                        session,
                        package.bottom_layers,
                        sample.dense_input);

                if (observation.outputs != sample.expected_bottom) {
                    throw std::runtime_error(
                        "FPGA bottom mismatch at pass " +
                        std::to_string(pass_index + 1u) +
                        " sample " +
                        std::to_string(sample.sample_id));
                }

                observed_bottom.push_back(observation.outputs);
                bottom_observations.push_back(observation);
                bottom_latency.add(observation);
                ++total_fpga_network_runs;
                total_fpga_output_values +=
                    observation.outputs.size();

                if ((sample_index + 1u) % 32u == 0u ||
                    sample_index + 1u == package.samples.size()) {
                    std::cout
                        << "HYBRID_PROGRESS phase=bottom"
                        << " pass=" << (pass_index + 1u)
                        << " samples=" << (sample_index + 1u)
                        << "/" << package.samples.size() << "\n";
                }
            }

            std::vector<std::vector<std::int16_t> > interactions;
            interactions.reserve(package.samples.size());
            for (std::size_t sample_index = 0;
                 sample_index < package.samples.size();
                 ++sample_index) {
                const HybridSample& sample =
                    package.samples[sample_index];
                const std::vector<std::int16_t> interaction =
                    cpu_interaction(
                        package,
                        observed_bottom[sample_index],
                        sample.categorical_ids);
                if (interaction != sample.expected_interaction) {
                    throw std::runtime_error(
                        "CPU interaction mismatch at pass " +
                        std::to_string(pass_index + 1u) +
                        " sample " +
                        std::to_string(sample.sample_id));
                }
                interactions.push_back(interaction);
                ++total_cpu_interactions;
            }

            top_descriptor_us +=
                program_descriptors(session, package.top_layers);

            for (std::size_t sample_index = 0;
                 sample_index < package.samples.size();
                 ++sample_index) {
                const HybridSample& sample =
                    package.samples[sample_index];
                const InferenceObservation top_observation =
                    run_network(
                        session,
                        package.top_layers,
                        interactions[sample_index]);

                if (top_observation.outputs != sample.expected_logit) {
                    throw std::runtime_error(
                        "FPGA top mismatch at pass " +
                        std::to_string(pass_index + 1u) +
                        " sample " +
                        std::to_string(sample.sample_id));
                }

                const std::uint32_t prediction =
                    top_observation.outputs[0] >= 0 ? 1u : 0u;
                const bool correct = prediction == sample.label;

                ++total_hybrid_inferences;
                ++total_fpga_network_runs;
                total_fpga_output_values +=
                    top_observation.outputs.size();
                ++exact_hybrid_inferences;
                if (correct) {
                    ++classification_correct;
                }
                top_latency.add(top_observation);

                csv << (pass_index + 1u) << ','
                    << sample.sample_id << ','
                    << sample.label << ','
                    << prediction << ','
                    << 1 << ','
                    << 1 << ','
                    << 1 << ','
                    << (correct ? 1 : 0) << ','
                    << vector_text(sample.expected_bottom) << ','
                    << vector_text(observed_bottom[sample_index]) << ','
                    << vector_text(sample.expected_interaction) << ','
                    << vector_text(interactions[sample_index]) << ','
                    << vector_text(sample.expected_logit) << ','
                    << vector_text(top_observation.outputs) << ','
                    << std::fixed << std::setprecision(3)
                    << bottom_observations[sample_index]
                           .first_result_latency_us << ','
                    << bottom_observations[sample_index]
                           .final_result_latency_us << ','
                    << top_observation.first_result_latency_us << ','
                    << top_observation.final_result_latency_us << ','
                    << "PASS\n";

                if ((sample_index + 1u) % 32u == 0u ||
                    sample_index + 1u == package.samples.size()) {
                    std::cout
                        << "HYBRID_PROGRESS phase=top"
                        << " pass=" << (pass_index + 1u)
                        << " samples=" << (sample_index + 1u)
                        << "/" << package.samples.size() << "\n";
                }
            }
        }

        csv.flush();
        if (!csv) {
            throw std::runtime_error(
                "failed while writing Stage 2M CSV");
        }

        const std::uint64_t expected_correct =
            verification.classification_correct * passes;
        if (classification_correct != expected_correct) {
            throw std::runtime_error(
                "hybrid classification count mismatch");
        }

        const double hybrid_count =
            static_cast<double>(total_hybrid_inferences);
        const double accuracy =
            static_cast<double>(classification_correct) /
            hybrid_count;

        std::cout
            << "TOTAL_HYBRID_INFERENCES="
            << total_hybrid_inferences << "\n"
            << "TOTAL_FPGA_NETWORK_RUNS="
            << total_fpga_network_runs << "\n"
            << "TOTAL_FPGA_OUTPUT_VALUES="
            << total_fpga_output_values << "\n"
            << "TOTAL_CPU_INTERACTIONS="
            << total_cpu_interactions << "\n"
            << "EXACT_HYBRID_INFERENCES="
            << exact_hybrid_inferences << "\n"
            << "NUMERICAL_MISMATCHES=0\n"
            << "CLASSIFICATION_CORRECT="
            << classification_correct << "\n"
            << "CLASSIFICATION_ACCURACY="
            << std::fixed << std::setprecision(6)
            << accuracy << "\n"
            << "BOTTOM_DESCRIPTOR_PROGRAM_US_TOTAL="
            << std::setprecision(3) << bottom_descriptor_us << "\n"
            << "TOP_DESCRIPTOR_PROGRAM_US_TOTAL="
            << top_descriptor_us << "\n"
            << "BOTTOM_FIRST_LATENCY_US_MIN="
            << bottom_latency.first_min << "\n"
            << "BOTTOM_FIRST_LATENCY_US_AVG="
            << bottom_latency.first_sum /
               static_cast<double>(bottom_latency.count) << "\n"
            << "BOTTOM_FIRST_LATENCY_US_MAX="
            << bottom_latency.first_max << "\n"
            << "BOTTOM_FINAL_LATENCY_US_MIN="
            << bottom_latency.final_min << "\n"
            << "BOTTOM_FINAL_LATENCY_US_AVG="
            << bottom_latency.final_sum /
               static_cast<double>(bottom_latency.count) << "\n"
            << "BOTTOM_FINAL_LATENCY_US_MAX="
            << bottom_latency.final_max << "\n"
            << "TOP_FIRST_LATENCY_US_MIN="
            << top_latency.first_min << "\n"
            << "TOP_FIRST_LATENCY_US_AVG="
            << top_latency.first_sum /
               static_cast<double>(top_latency.count) << "\n"
            << "TOP_FIRST_LATENCY_US_MAX="
            << top_latency.first_max << "\n"
            << "TOP_FINAL_LATENCY_US_MIN="
            << top_latency.final_min << "\n"
            << "TOP_FINAL_LATENCY_US_AVG="
            << top_latency.final_sum /
               static_cast<double>(top_latency.count) << "\n"
            << "TOP_FINAL_LATENCY_US_MAX="
            << top_latency.final_max << "\n"
            << "STAGE2M_HYBRID_DLRM_PASS"
            << " model=" << package.name
            << " passes=" << passes
            << " samples=" << package.samples.size()
            << " hybrid_inferences="
            << total_hybrid_inferences
            << " fpga_network_runs="
            << total_fpga_network_runs
            << " exact=" << exact_hybrid_inferences
            << " accuracy=" << std::setprecision(6)
            << accuracy << "\n";

        return EXIT_SUCCESS;
    }
    catch (const std::exception& error) {
        std::cerr << "STAGE2M_HYBRID_DLRM_FAILED: "
                  << error.what() << "\n";
        return EXIT_FAILURE;
    }
}
