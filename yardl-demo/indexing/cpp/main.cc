#include <random>
#include <sstream>

#include "generated/binary/protocols.h"

#define VALIDATE(cond, msg)                                                                \
  if (!(cond)) {                                                                           \
    std::cerr << "Assertion failed: " << msg << " (Line " << __LINE__ << ")" << std::endl; \
    exit(1);                                                                               \
  }

int main(void) {
  std::stringstream output;

  sketch::binary::MyProtocolWriter writer(output);
  writer.WriteHeader(sketch::Header{"John Doe"});

  std::cout << "Writing samples... ";
  size_t sample_count = 0;
  std::vector<sketch::Sample> samples(44);
  for (auto& sample : samples) {
    sample.id = sample_count++;
    sample.data = xt::arange<int32_t>(sample_count, sample_count + 2000);
    std::cout << sample.id << " ";
  }
  std::cout << ", ";

  writer.WriteSamples(samples);

  samples.resize(22);
  for (auto& sample : samples) {
    sample.id = sample_count++;
    sample.data = xt::arange<int32_t>(sample_count, sample_count + 2000);
    writer.WriteSamples(sample);
    std::cout << sample.id << ", ";
  }

  samples.resize(33);
  for (auto& sample : samples) {
    sample.id = sample_count++;
    sample.data = xt::arange<int32_t>(sample_count, sample_count + 2000);
    std::cout << sample.id << " ";
  }
  std::cout << std::endl;
  writer.WriteSamples(samples);

  writer.EndSamples();
  writer.Close();

  auto serialized_without_index = output.str();

  // Try to load IndexedReader without an index. Should throw an exception.
  {
    bool caught_expected = false;
    std::stringstream input(serialized_without_index);
    try {
      sketch::binary::MyProtocolIndexedReader reader(input);
    } catch (std::exception const& ex) {
      caught_expected = true;
    }

    VALIDATE(caught_expected, "Expected MyProtocolIndexedReader to throw exception!");
  }

  output = std::stringstream{};

  // Copy the protocol stream to a new stream with indexing
  {
    std::stringstream input(serialized_without_index);
    sketch::binary::MyProtocolReader reader(input);

    sketch::binary::MyProtocolIndexedWriter writer(output);

    reader.CopyTo(writer);
    reader.Close();
    writer.Close();
  }

  auto serialized_with_index = output.str();

  // Test reading streams without the Index
  {
    {
      std::stringstream input(serialized_with_index);
      sketch::binary::MyProtocolIndexedReader reader(input);

      sketch::Sample sample;
      size_t idx = 0;
      std::cout << "Reading samples... ";
      while (reader.ReadSamples(sample)) {
        VALIDATE(sample.id == idx++, "Failed to read correct sample");
        std::cout << sample.id << " ";
      }
      std::cout << std::endl;
      VALIDATE(reader.CountSamples() == sample_count, "Failed to get correct sample count");
      VALIDATE(idx == sample_count, "Failed to read all samples");

      // Read the Header *after* reading the entire stream
      sketch::Header header;
      reader.ReadHeader(header);

      reader.Close();
    }

    {
      std::stringstream input(serialized_with_index);
      sketch::binary::MyProtocolIndexedReader reader(input);

      // First, read a few samples from the middle of the stream
      std::vector<sketch::Sample> samples;
      samples.reserve(9);
      auto idx = reader.CountSamples() / 2;
      std::cout << "Reading samples... ";
      VALIDATE(reader.ReadSamples(samples, idx), "Failed to read samples from the middle of the stream");
      for (auto const& sample : samples) {
        VALIDATE(sample.id == idx++, "Failed to read correct sample");
        std::cout << sample.id << " ";
      }
      std::cout << ", continuing... ";

      // Then, read the *rest* of the stream without specifying an index
      while (reader.ReadSamples(samples)) {
        for (auto& sample : samples) {
          VALIDATE(sample.id == idx++, "Failed to read correct sample");
          std::cout << sample.id << " ";
        }
        std::cout << ", ";
      }
      std::cout << std::endl;
      VALIDATE(idx == sample_count, "Failed to read all samples");

      reader.Close();
    }
  }

  // Test reading stream element-by-element using the Index
  {
    std::stringstream input(serialized_with_index);
    sketch::binary::MyProtocolIndexedReader reader(input);

    std::random_device rd;
    std::mt19937 g(rd());

    VALIDATE(reader.CountSamples() == sample_count, "CountSamples() failed");

    std::vector<size_t> indices(reader.CountSamples());
    for (size_t i = 0; i < reader.CountSamples(); i++) {
      indices[i] = i;
    }
    std::shuffle(indices.begin(), indices.end(), g);


    std::cout << "Reading samples... ";
    sketch::Sample sample;
    for (size_t idx : indices) {
      VALIDATE(reader.ReadSamples(sample, idx), "Failed to read sample");
      std::cout << sample.id << " ";
      VALIDATE(sample.id == idx, "Failed to read correct sample");
    }
    std::cout << std::endl;

    reader.Close();
  }

  // Test batch reading stream from index
  {
    std::stringstream input(serialized_with_index);
    sketch::binary::MyProtocolIndexedReader reader(input);

    std::vector<sketch::Sample> samples;
    samples.reserve(3);
    size_t idx = 0;
    std::cout << "Reading samples... ";
    while (reader.ReadSamples(samples, idx)) {
      // Do something with samples
      for (auto const& sample : samples) {
        std::cout << sample.id << " ";
      }
      idx += samples.size();
      std::cout << ", ";
    }
    std::cout << std::endl;
    VALIDATE(idx == sample_count, "Batch read all samples failed");
    reader.Close();
  }

  // Test indexing with an empty stream
  {
    std::stringstream output;

    sketch::binary::MyProtocolIndexedWriter writer(output);
    writer.WriteHeader(sketch::Header{"John Doe"});

    writer.EndSamples();
    writer.Close();

    auto serialized = output.str();

    std::stringstream input(serialized);
    sketch::binary::MyProtocolIndexedReader reader(input);

    VALIDATE(reader.CountSamples() == 0, "CountSamples() failed");

    sketch::Sample sample;
    size_t idx = 0;
    while (reader.ReadSamples(sample, idx)) {
      // Do something with samples
      idx += 1;
    }
    VALIDATE(idx == 0, "Read empty samples failed");
    reader.Close();
  }

  std::cout << "Success!" << std::endl;
  return 0;
}
