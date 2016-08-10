// featbin/wav-addnoise.cc

// Copyright 2016   LingoChamp Feiteng

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "feat/wave-reader.h"
#include "feat/signal.h"

namespace kaldi {

/*
   This function is to repeatedly concatenate signal1 by itself 
   to match the length of signal2 and add the two signals together.
*/
void AddVectorsOfUnequalLength(const Vector<BaseFloat> &signal1, Vector<BaseFloat> *signal2) {
  for (int32 po = 0; po < signal2->Dim(); po += signal1.Dim()) {
    int32 block_length = signal1.Dim();
    if (signal2->Dim() - po < block_length) block_length = signal2->Dim() - po;
    signal2->Range(po, block_length).AddVec(1.0, signal1.Range(0, block_length));
  }
}

BaseFloat MaxAbsolute(const Vector<BaseFloat> &vector) {
  return std::max(std::abs(vector.Max()), std::abs(vector.Min()));
}

/*
   This is the core function to do noise addition on the given signal. 
   The noise will be scaled before the addition
   to match the given signal-to-noise ratio (SNR) and it will also concatenate
   itself repeatedly to match the length of the signal.
   The input parameters to this function are the sampling frequency,
   the SNR(dB), the noise and the signal respectively.
*/
void CorruptsNoise(BaseFloat snr_db, Vector<BaseFloat> *noise,
                        Vector<BaseFloat> *signal) {

  float input_power = VecVec(*signal, *signal) / signal->Dim();
  float noise_power = VecVec(*noise, *noise) / noise->Dim();
  float scale_factor = sqrt(pow(10, -snr_db / 10) * input_power / noise_power);
  noise->Scale(scale_factor);
  KALDI_VLOG(1) << "Noise signal is being scaled with " << scale_factor
                << " to generate output with SNR " << snr_db << "db\n";
  AddVectorsOfUnequalLength(*noise, signal);
}

}

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Corrupts the wave files supplied with noise distortions\n"
        "Usage:  wav-addnoise [options...] <wav-in-rxfilename> "
        "<noise-rxfilename> <wav-out-wxfilename>\n"
        "e.g.\n"
        "wav-addnoise input.wav noise.wav output.wav\n";

    ParseOptions po(usage);
    BaseFloat snr_db = 20;
    bool multi_channel_output = false;
    int32 input_channel = 0;
    int32 noise_channel = 0;
    bool normalize_output = true;
    BaseFloat volume = 0;
    BaseFloat shift = 0;

    po.Register("multi-channel-output", &multi_channel_output,
                "Specifies if the output should be multi-channel or not");
    po.Register("input-wave-channel", &input_channel,
                "Specifies the channel to be used from input as only a "
                "single channel will be used to generate reverberated output");
    po.Register("noise-channel", &noise_channel,
                "Specifies the channel of the noise file, "
                "it will only be used when multi-channel-output is false");
    po.Register("snr-db", &snr_db,
                "Desired SNR(dB) of the output");
    po.Register("normalize-output", &normalize_output,
                "If true, then after reverberating and "
                "possibly adding noise, scale so that the signal "
                "energy is the same as the original input signal.");
    po.Register("volume", &volume,
                "If nonzero, a scaling factor on the signal that is applied "
                "after reverberating and possibly adding noise. "
                "If you set this option to a nonzero value, it will be as"
                "if you had also specified --normalize-output=false.");
    po.Register("shift", &shift,
                "Shift noise data, unit is second.");

    po.Read(argc, argv);
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string input_wave_file = po.GetArg(1);
    std::string noise_wave_file = po.GetArg(2);
    std::string output_wave_file = po.GetArg(3);

    WaveData input_wave;
    {
      Input ki(input_wave_file);
      input_wave.Read(ki.Stream());
    }

    const Matrix<BaseFloat> &input_matrix = input_wave.Data();
    BaseFloat samp_freq_input = input_wave.SampFreq();
    int32 num_samp_input = input_matrix.NumCols(),  // #samples in the input
          num_input_channel = input_matrix.NumRows();  // #channels in the input
    KALDI_VLOG(1) << "sampling frequency of input: " << samp_freq_input
                  << " #samples: " << num_samp_input
                  << " #channel: " << num_input_channel;
    KALDI_ASSERT(input_channel < num_input_channel);

    WaveData noise_wave;
    {
      Input ki(noise_wave_file);
      noise_wave.Read(ki.Stream());
    }
    Matrix<BaseFloat> noise_matrix = noise_wave.Data();
    BaseFloat samp_freq_noise = noise_wave.SampFreq();
    KALDI_ASSERT(samp_freq_noise == samp_freq_input);
    if (shift * samp_freq_noise > noise_matrix.NumCols()) {
      KALDI_WARN << "Shift is larger than duration, set to 0.";
      shift = 0;
    }
    if (shift && (num_samp_input > noise_matrix.NumCols() - samp_freq_noise * shift)) {
      Matrix<BaseFloat> noise = noise_matrix;
      int32 offset = samp_freq_noise * shift;
      KALDI_ASSERT(noise.NumCols() > 0);
      noise_matrix.Resize(noise_matrix.NumRows(), noise.NumCols() * 2 - offset);
      noise_matrix.ColRange(0, noise.NumCols() - offset).CopyFromMat(noise.ColRange(offset, noise.NumCols() - offset));
      noise_matrix.ColRange(noise.NumCols() - offset, noise.NumCols()).CopyFromMat(noise);
    }
    int32 num_samp_noise = noise_matrix.NumCols(),
          num_noise_channel = noise_matrix.NumRows();
    KALDI_VLOG(1) << "sampling frequency of noise: " << samp_freq_noise
                  << " #samples: " << num_samp_noise
                  << " #channel: " << num_noise_channel;
    KALDI_ASSERT(noise_channel < num_noise_channel);

    int32 num_channels = (multi_channel_output ? num_input_channel : 1);
    Matrix<BaseFloat> out_matrix(num_channels, num_samp_input);

    for (int32 channel = 0; channel < num_channels; channel++) {
      Vector<BaseFloat> input(num_samp_input);
      input.CopyRowFromMat(input_matrix, channel);
      float power_before_addnoise = VecVec(input, input) / input.Dim();

      Vector<BaseFloat> noise(noise_matrix.NumCols());
      int32 this_noise_channel = ((noise_channel > 0) ? noise_channel : channel) % num_noise_channel;
      noise.CopyRowFromMat(noise_matrix, this_noise_channel);

      CorruptsNoise(snr_db, &noise, &input);
      float power_after_addnoise = VecVec(input, input) / input.Dim();

      if (volume > 0)
        input.Scale(volume);
      else if (normalize_output)
        input.Scale(sqrt(power_before_addnoise / power_after_addnoise));

      out_matrix.CopyRowFromVec(input, channel);
    }

    WaveData out_wave(samp_freq_input, out_matrix);
    Output ko(output_wave_file, false);
    out_wave.Write(ko.Stream());

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

