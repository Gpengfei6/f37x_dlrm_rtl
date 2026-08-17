#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <numeric>

#define main stage2n_a11_embedded_main
#include "stage2n_a11_real_model_batch_board_v1.cpp"
#undef main

namespace {

using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;

long long elapsed_ns(const TimePoint& begin, const TimePoint& end)
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        end - begin).count();
}

double ns_to_us(long long value)
{
    return static_cast<double>(value) / 1000.0;
}

struct SampleTiming
{
    long long prepare_idle_ns = 0;
    long long input_program_ns = 0;
    long long start_issue_ns = 0;
    long long wait_valid_ns = 0;
    long long result_read_ns = 0;
    long long retire_ns = 0;
    long long total_ns = 0;
};

struct TimedRunResult
{
    RunResult result;
    SampleTiming timing;
};

struct Distribution
{
    double minimum_us = 0.0;
    double p50_us = 0.0;
    double p95_us = 0.0;
    double p99_us = 0.0;
    double mean_us = 0.0;
    double maximum_us = 0.0;
};

std::size_t percentile_index(std::size_t count, double percentile)
{
    if (count == 0u) {
        throw std::runtime_error(
            "cannot compute percentile of empty sample set");
    }

    const double rank =
        std::ceil(percentile * static_cast<double>(count));
    const std::size_t one_based =
        std::max<std::size_t>(
            1u,
            static_cast<std::size_t>(rank));
    return std::min<std::size_t>(count, one_based) - 1u;
}

Distribution summarize_ns(const std::vector<long long>& values)
{
    if (values.empty()) {
        throw std::runtime_error(
            "cannot summarize empty timing vector");
    }

    std::vector<long long> ordered(values);
    std::sort(ordered.begin(), ordered.end());

    long double total_ns = 0.0;
    for (std::size_t index = 0; index < values.size(); ++index) {
        total_ns += static_cast<long double>(values[index]);
    }

    Distribution result;
    result.minimum_us = ns_to_us(ordered.front());
    result.p50_us = ns_to_us(
        ordered[percentile_index(ordered.size(), 0.50)]);
    result.p95_us = ns_to_us(
        ordered[percentile_index(ordered.size(), 0.95)]);
    result.p99_us = ns_to_us(
        ordered[percentile_index(ordered.size(), 0.99)]);
    result.mean_us = static_cast<double>(
        total_ns /
        static_cast<long double>(values.size()) /
        1000.0L);
    result.maximum_us = ns_to_us(ordered.back());
    return result;
}

void print_distribution(
    const std::string& prefix,
    const Distribution& value)
{
    std::cout
        << std::fixed << std::setprecision(3)
        << prefix << "_MIN_US=" << value.minimum_us << "\n"
        << prefix << "_P50_US=" << value.p50_us << "\n"
        << prefix << "_P95_US=" << value.p95_us << "\n"
        << prefix << "_P99_US=" << value.p99_us << "\n"
        << prefix << "_MEAN_US=" << value.mean_us << "\n"
        << prefix << "_MAX_US=" << value.maximum_us << "\n";
}

unsigned parse_positive_unsigned(
    const char* text,
    const char* name,
    unsigned maximum)
{
    if (!text || !*text) {
        throw std::runtime_error(
            std::string(name) + " is empty");
    }

    char* end = nullptr;
    const unsigned long value = std::strtoul(text, &end, 10);
    if (*end != '\0' || value == 0ul || value > maximum) {
        throw std::runtime_error(
            std::string(name) +
            " must be in [1, " +
            std::to_string(maximum) + "]");
    }

    return static_cast<unsigned>(value);
}

TimedRunResult run_sample_timed(
    Hal& hal,
    const Sample& sample)
{
    TimedRunResult output;

    const TimePoint total_begin = Clock::now();

    const TimePoint prepare_begin = Clock::now();
    prepare_idle(hal);
    const TimePoint prepare_end = Clock::now();
    output.timing.prepare_idle_ns =
        elapsed_ns(prepare_begin, prepare_end);

    const TimePoint input_begin = Clock::now();
    configure_sample(hal, sample);
    const TimePoint input_end = Clock::now();
    output.timing.input_program_ns =
        elapsed_ns(input_begin, input_end);

    const TimePoint start_begin = Clock::now();
    start_pipeline(hal);
    const TimePoint start_end = Clock::now();
    output.timing.start_issue_ns =
        elapsed_ns(start_begin, start_end);

    const TimePoint wait_begin = Clock::now();
    std::uint32_t status = poll_status(
        hal,
        [](std::uint32_t value) {
            return (value & S_VALID) != 0;
        },
        "A12 pipeline sample result",
        10000);
    const TimePoint wait_end = Clock::now();
    output.timing.wait_valid_ns =
        elapsed_ns(wait_begin, wait_end);

    const TimePoint read_begin = Clock::now();
    output.result.logit =
        static_cast<std::int32_t>(hal.read(A_RESULT_DATA));
    output.result.result_index =
        hal.read(A_RESULT_INDEX) & 0x3Fu;

    const std::uint32_t result_meta = hal.read(A_RESULT_META);
    output.result.result_tag =
        (result_meta >> 16) & 0xFFu;
    output.result.prediction =
        output.result.logit >= 0 ? 1u : 0u;

    if ((status & S_LAST) == 0u ||
        (result_meta & 0x3u) != 0x3u) {
        throw std::runtime_error(
            "A12 result valid/last metadata mismatch");
    }
    if (output.result.result_index != 0u) {
        throw std::runtime_error(
            "A12 result index mismatch");
    }
    if (output.result.result_tag != EXPECTED_FINAL_TAG) {
        throw std::runtime_error(
            "A12 result descriptor tag mismatch");
    }
    const TimePoint read_end = Clock::now();
    output.timing.result_read_ns =
        elapsed_ns(read_begin, read_end);

    const TimePoint retire_begin = Clock::now();
    hal.write(A_CTL, CMD_POP);

    status = poll_status(
        hal,
        [](std::uint32_t value) {
            return
                (value & S_DONE) != 0 &&
                (value &
                 (S_BUSY | S_VALID | S_PENDING)) == 0;
        },
        "A12 pipeline terminal done",
        10000);

    const std::uint32_t result_count =
        hal.read(A_RESULT_COUNT);
    const std::uint32_t phase_counts =
        hal.read(A_PHASE_COUNTS);

    output.result.bottom_count =
        (phase_counts >> 8) & 0xFu;
    output.result.interaction_count =
        (phase_counts >> 16) & 0x1Fu;

    if (result_count != 1u) {
        throw std::runtime_error(
            "A12 result count mismatch");
    }
    if (output.result.bottom_count !=
        EXPECTED_EMBEDDING_DIM) {
        throw std::runtime_error(
            "A12 bottom output count mismatch");
    }
    if (output.result.interaction_count !=
        EXPECTED_INTERACTION_DIM) {
        throw std::runtime_error(
            "A12 interaction output count mismatch");
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
        "A12 pipeline idle after clear done",
        2000);
    const TimePoint retire_end = Clock::now();
    output.timing.retire_ns =
        elapsed_ns(retire_begin, retire_end);

    const TimePoint total_end = Clock::now();
    output.timing.total_ns =
        elapsed_ns(total_begin, total_end);

    return output;
}

void verify_result(
    const Sample& sample,
    const RunResult& result,
    const std::string& phase,
    unsigned pass_index)
{
    if (result.logit !=
        static_cast<std::int32_t>(sample.expected_logit)) {
        throw std::runtime_error(
            phase + " FPGA/reference logit mismatch at pass " +
            std::to_string(pass_index) +
            " sample " + std::to_string(sample.sample_id) +
            ": expected=" +
            std::to_string(sample.expected_logit) +
            " actual=" + std::to_string(result.logit));
    }

    if (result.prediction != sample.expected_prediction) {
        throw std::runtime_error(
            phase +
            " FPGA/reference prediction mismatch at pass " +
            std::to_string(pass_index) +
            " sample " + std::to_string(sample.sample_id));
    }
}

void write_sample_header(std::ofstream& output)
{
    output
        << "measured_pass,sample_id,label,expected_logit,"
        << "fpga_logit,expected_prediction,fpga_prediction,"
        << "classification_correct,result_index,result_tag,"
        << "bottom_count,interaction_count,"
        << "prepare_idle_us,input_program_us,start_issue_us,"
        << "wait_valid_us,result_read_us,retire_us,total_us\n";
}

void write_pass_header(std::ofstream& output)
{
    output
        << "measured_pass,samples,pass_total_us,"
        << "throughput_samples_per_sec,logit_exact,"
        << "prediction_exact,classification_correct\n";
}

}  // namespace

int main(int argc, char** argv)
{
    try {
        if (argc != 6) {
            std::cerr
                << "Usage: " << argv[0]
                << " <stage2n_a11_real_model_batch_v2.f37xpb>"
                << " <sample_timing.csv>"
                << " <pass_summary.csv>"
                << " <warmup_passes>"
                << " <measured_passes>\n";
            return 2;
        }

        const std::string asset_path = argv[1];
        const std::string sample_csv_path = argv[2];
        const std::string pass_csv_path = argv[3];
        const unsigned warmup_passes =
            parse_positive_unsigned(
                argv[4], "warmup_passes", 100u);
        const unsigned measured_passes =
            parse_positive_unsigned(
                argv[5], "measured_passes", 1000u);

        const std::uint64_t measured_samples =
            static_cast<std::uint64_t>(measured_passes) *
            EXPECTED_SAMPLE_COUNT;

        std::cout
            << "Stage 2N-A12 automatic-pipeline performance baseline v1\n"
            << "Access=xclOpenContext+xclRegRead+xclRegWrite\n"
            << "ASSET_PATH=" << asset_path << "\n"
            << "SAMPLE_TIMING_CSV=" << sample_csv_path << "\n"
            << "PASS_SUMMARY_CSV=" << pass_csv_path << "\n"
            << "WARMUP_PASSES=" << warmup_passes << "\n"
            << "MEASURED_PASSES=" << measured_passes << "\n"
            << "MEASURED_SAMPLES=" << measured_samples << "\n"
            << "TIMING_SCOPE=host-visible register-driven latency\n"
            << "CLAIM_BOUNDARY=deterministic synthetic Stage 2M "
            << "trained-model regression; not real Criteo evidence\n";

        const BatchAsset asset = load_asset(asset_path);

        std::ofstream sample_csv(sample_csv_path.c_str());
        if (!sample_csv) {
            throw std::runtime_error(
                "cannot open sample timing CSV: " +
                sample_csv_path);
        }
        write_sample_header(sample_csv);

        std::ofstream pass_csv(pass_csv_path.c_str());
        if (!pass_csv) {
            throw std::runtime_error(
                "cannot open pass summary CSV: " +
                pass_csv_path);
        }
        write_pass_header(pass_csv);

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

        if (mlp_version != EXPECTED_MLP_VERSION ||
            interaction_version != EXPECTED_INT_VERSION ||
            pipeline_version != EXPECTED_PIPE_VERSION) {
            throw std::runtime_error(
                "A12 hardware version mismatch");
        }

        const TimePoint static_begin = Clock::now();
        prepare_idle(hal);
        configure_static_model(hal, asset);
        const TimePoint static_end = Clock::now();
        const long long static_config_ns =
            elapsed_ns(static_begin, static_end);

        std::cout
            << std::fixed << std::setprecision(3)
            << "STATIC_MODEL_CONFIG_US="
            << ns_to_us(static_config_ns) << "\n";

        unsigned warmup_logit_exact = 0u;
        unsigned warmup_prediction_exact = 0u;

        for (unsigned pass = 0;
             pass < warmup_passes;
             ++pass) {
            for (std::size_t sample_index = 0;
                 sample_index < asset.samples.size();
                 ++sample_index) {
                const Sample& sample =
                    asset.samples[sample_index];
                const RunResult result =
                    run_sample(hal, sample);
                verify_result(
                    sample, result, "warmup", pass);

                ++warmup_logit_exact;
                ++warmup_prediction_exact;
            }

            std::cout
                << "A12_WARMUP_PASS_COMPLETE="
                << (pass + 1u) << "/"
                << warmup_passes << "\n";
        }

        const unsigned expected_warmup_exact =
            warmup_passes * EXPECTED_SAMPLE_COUNT;
        if (warmup_logit_exact != expected_warmup_exact ||
            warmup_prediction_exact != expected_warmup_exact) {
            throw std::runtime_error(
                "A12 warmup exact-count mismatch");
        }

        std::vector<long long> prepare_values;
        std::vector<long long> input_values;
        std::vector<long long> start_values;
        std::vector<long long> wait_values;
        std::vector<long long> read_values;
        std::vector<long long> retire_values;
        std::vector<long long> total_values;
        std::vector<long long> pass_values;

        prepare_values.reserve(measured_samples);
        input_values.reserve(measured_samples);
        start_values.reserve(measured_samples);
        wait_values.reserve(measured_samples);
        read_values.reserve(measured_samples);
        retire_values.reserve(measured_samples);
        total_values.reserve(measured_samples);
        pass_values.reserve(measured_passes);

        std::uint64_t logit_exact = 0u;
        std::uint64_t prediction_exact = 0u;
        std::uint64_t classification_correct = 0u;

        const TimePoint measured_batch_begin = Clock::now();
        long long measured_execution_ns = 0;

        for (unsigned pass = 0;
             pass < measured_passes;
             ++pass) {
            long long pass_execution_ns = 0;

            unsigned pass_logit_exact = 0u;
            unsigned pass_prediction_exact = 0u;
            unsigned pass_classification_correct = 0u;

            for (std::size_t sample_index = 0;
                 sample_index < asset.samples.size();
                 ++sample_index) {
                const Sample& sample =
                    asset.samples[sample_index];
                const TimedRunResult timed =
                    run_sample_timed(hal, sample);

                verify_result(
                    sample,
                    timed.result,
                    "measured",
                    pass);

                const bool classification_is_correct =
                    timed.result.prediction == sample.label;

                ++logit_exact;
                ++prediction_exact;
                ++pass_logit_exact;
                ++pass_prediction_exact;

                if (classification_is_correct) {
                    ++classification_correct;
                    ++pass_classification_correct;
                }

                prepare_values.push_back(
                    timed.timing.prepare_idle_ns);
                input_values.push_back(
                    timed.timing.input_program_ns);
                start_values.push_back(
                    timed.timing.start_issue_ns);
                wait_values.push_back(
                    timed.timing.wait_valid_ns);
                read_values.push_back(
                    timed.timing.result_read_ns);
                retire_values.push_back(
                    timed.timing.retire_ns);
                total_values.push_back(
                    timed.timing.total_ns);
                pass_execution_ns +=
                    timed.timing.total_ns;

                sample_csv
                    << (pass + 1u) << ","
                    << sample.sample_id << ","
                    << sample.label << ","
                    << sample.expected_logit << ","
                    << timed.result.logit << ","
                    << sample.expected_prediction << ","
                    << timed.result.prediction << ","
                    << (classification_is_correct ? 1 : 0) << ","
                    << timed.result.result_index << ","
                    << timed.result.result_tag << ","
                    << timed.result.bottom_count << ","
                    << timed.result.interaction_count << ","
                    << std::fixed << std::setprecision(3)
                    << ns_to_us(
                           timed.timing.prepare_idle_ns) << ","
                    << ns_to_us(
                           timed.timing.input_program_ns) << ","
                    << ns_to_us(
                           timed.timing.start_issue_ns) << ","
                    << ns_to_us(
                           timed.timing.wait_valid_ns) << ","
                    << ns_to_us(
                           timed.timing.result_read_ns) << ","
                    << ns_to_us(
                           timed.timing.retire_ns) << ","
                    << ns_to_us(
                           timed.timing.total_ns) << "\n";
            }

            const long long pass_ns =
                pass_execution_ns;
            measured_execution_ns += pass_ns;
            pass_values.push_back(pass_ns);

            const double pass_us = ns_to_us(pass_ns);
            const double throughput =
                static_cast<double>(EXPECTED_SAMPLE_COUNT) *
                1000000.0 / pass_us;

            pass_csv
                << (pass + 1u) << ","
                << EXPECTED_SAMPLE_COUNT << ","
                << std::fixed << std::setprecision(3)
                << pass_us << ","
                << throughput << ","
                << pass_logit_exact << ","
                << pass_prediction_exact << ","
                << pass_classification_correct << "\n";

            if (pass_logit_exact != EXPECTED_SAMPLE_COUNT ||
                pass_prediction_exact != EXPECTED_SAMPLE_COUNT ||
                pass_classification_correct !=
                    EXPECTED_CLASSIFICATION_CORRECT) {
                throw std::runtime_error(
                    "A12 measured pass exact-count mismatch");
            }

            std::cout
                << std::fixed << std::setprecision(3)
                << "A12_MEASURED_PASS_COMPLETE="
                << (pass + 1u) << "/"
                << measured_passes
                << " PASS_TOTAL_US=" << pass_us
                << " PASS_THROUGHPUT_SAMPLES_PER_SEC="
                << throughput << "\n";
        }

        const TimePoint measured_batch_end = Clock::now();
        const long long instrumented_wall_ns =
            elapsed_ns(
                measured_batch_begin,
                measured_batch_end);
        const double measured_batch_us =
            ns_to_us(measured_execution_ns);
        const double instrumented_wall_us =
            ns_to_us(instrumented_wall_ns);
        const double host_visible_throughput =
            static_cast<double>(measured_samples) *
            1000000.0 / measured_batch_us;
        const double instrumented_wall_throughput =
            static_cast<double>(measured_samples) *
            1000000.0 / instrumented_wall_us;

        sample_csv.close();
        pass_csv.close();
        if (!sample_csv || !pass_csv) {
            throw std::runtime_error(
                "A12 timing CSV write failure");
        }

        const std::uint64_t expected_exact =
            static_cast<std::uint64_t>(measured_passes) *
            EXPECTED_SAMPLE_COUNT;
        const std::uint64_t expected_correct =
            static_cast<std::uint64_t>(measured_passes) *
            EXPECTED_CLASSIFICATION_CORRECT;

        if (logit_exact != expected_exact ||
            prediction_exact != expected_exact ||
            classification_correct != expected_correct) {
            throw std::runtime_error(
                "A12 aggregate correctness mismatch");
        }

        const Distribution prepare_stats =
            summarize_ns(prepare_values);
        const Distribution input_stats =
            summarize_ns(input_values);
        const Distribution start_stats =
            summarize_ns(start_values);
        const Distribution wait_stats =
            summarize_ns(wait_values);
        const Distribution read_stats =
            summarize_ns(read_values);
        const Distribution retire_stats =
            summarize_ns(retire_values);
        const Distribution total_stats =
            summarize_ns(total_values);
        const Distribution pass_stats =
            summarize_ns(pass_values);

        print_distribution(
            "PREPARE_IDLE_LATENCY", prepare_stats);
        print_distribution(
            "INPUT_PROGRAM_LATENCY", input_stats);
        print_distribution(
            "START_ISSUE_LATENCY", start_stats);
        print_distribution(
            "WAIT_VALID_LATENCY", wait_stats);
        print_distribution(
            "RESULT_READ_LATENCY", read_stats);
        print_distribution(
            "RETIRE_LATENCY", retire_stats);
        print_distribution(
            "TOTAL_SAMPLE_LATENCY", total_stats);
        print_distribution(
            "PASS_256_LATENCY", pass_stats);

        const double input_fraction =
            total_stats.mean_us > 0.0
                ? input_stats.mean_us /
                      total_stats.mean_us
                : 0.0;
        const double wait_fraction =
            total_stats.mean_us > 0.0
                ? wait_stats.mean_us /
                      total_stats.mean_us
                : 0.0;
        const double control_fraction =
            total_stats.mean_us > 0.0
                ? (
                    prepare_stats.mean_us +
                    start_stats.mean_us +
                    read_stats.mean_us +
                    retire_stats.mean_us) /
                      total_stats.mean_us
                : 0.0;

        std::cout
            << std::fixed << std::setprecision(6)
            << "INPUT_PROGRAM_FRACTION="
            << input_fraction << "\n"
            << "WAIT_VALID_FRACTION="
            << wait_fraction << "\n"
            << "CONTROL_AND_RETIRE_FRACTION="
            << control_fraction << "\n"
            << std::setprecision(3)
            << "MEASURED_BATCH_TOTAL_US="
            << measured_batch_us << "\n"
            << "INSTRUMENTED_WALL_TOTAL_US="
            << instrumented_wall_us << "\n"
            << "HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC="
            << host_visible_throughput << "\n"
            << "INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC="
            << instrumented_wall_throughput << "\n"
            << "WARMUP_LOGIT_EXACT="
            << warmup_logit_exact << "\n"
            << "WARMUP_PREDICTION_EXACT="
            << warmup_prediction_exact << "\n"
            << "MEASURED_LOGIT_EXACT="
            << logit_exact << "\n"
            << "MEASURED_PREDICTION_EXACT="
            << prediction_exact << "\n"
            << "MEASURED_CLASSIFICATION_CORRECT="
            << classification_correct << "\n"
            << "NO_FPGA_PROGRAMMING=1\n"
            << "NO_FPGA_RESET=1\n"
            << "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1_PASS "
            << "warmup_passes=" << warmup_passes
            << " measured_passes=" << measured_passes
            << " measured_samples=" << measured_samples
            << " logit_exact=" << logit_exact
            << " prediction_exact=" << prediction_exact
            << "\n";

        return 0;
    } catch (const std::exception& error) {
        std::cerr
            << "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1_FAILED: "
            << error.what() << "\n";
        return 1;
    }
}
