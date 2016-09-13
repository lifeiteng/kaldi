// nnet3bin/nnet3-chain-train.cc

// Copyright 2015  Johns Hopkins University (author: Daniel Povey)

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
#include "thread/kaldi-task-sequence.h"
#include "nnet3/nnet-chain-training.h"

namespace kaldi {
namespace nnet3 {

struct NnetChainParallelTrainingOptions {
  NnetChainTrainingOptions train_config;
  bool binary_write;
  std::string use_gpu;
  NnetChainParallelTrainingOptions():
    binary_write(true),
    use_gpu("yes") {
  }

  void Register(OptionsItf *opts) {
    train_config.Register(opts);
    opts->Register("binary", &binary_write, "Write output in binary mode");
    opts->Register("use-gpu", &use_gpu, "GPUS config yse|no|wait");
  }
};

class NnetChainTrainerThread {
 public:
  NnetChainTrainerThread(const NnetChainParallelTrainingOptions &opts,
                         int32 gpu_id,
                         const chain::DenominatorGraph &den_graph,
                         const nnet3::Nnet &nnet,
                         const std::string &examples_rspecifier,
                         const std::string &nnet_wxfilename):
    opts_(opts),
    gpu_id_(gpu_id),
    den_graph_(den_graph),
    nnet_(nnet),
    examples_rspecifier_(examples_rspecifier),
    nnet_wxfilename_(nnet_wxfilename) {

    sub_nnet_ = NULL;
#if HAVE_CUDA==1
    if (opts_.use_gpu == "no" || gpu_id_ < 0) {
      CuDevice::Instantiate().SelectGpuId(opts_.use_gpu);
    } else if (gpu_id_ >= 0) {
      CuDevice::Instantiate().SelectGpuId(gpu_id_);
    }
#endif
    }

    void operator() () {
      sub_nnet_ = nnet_.Copy();
      NnetChainTrainer trainer(opts_.train_config, den_graph_, sub_nnet_);

      SequentialNnetChainExampleReader example_reader(examples_rspecifier_);
      for (; !example_reader.Done(); example_reader.Next())
        trainer.Train(example_reader.Value());

      done_ = trainer.PrintTotalStats();
    }

    ~NnetChainTrainerThread() {
      // write model
      KALDI_LOG << "Wrote raw model to " << nnet_wxfilename_;
      WriteKaldiObject(*sub_nnet_, nnet_wxfilename_, opts_.binary_write);
      KALDI_ASSERT(sub_nnet_ != NULL);
      delete sub_nnet_;

      KALDI_ASSERT(done_);

#if HAVE_CUDA==1
      CuDevice::Instantiate().PrintProfile();
      CuDevice::Instantiate().DeviceReset();
#endif
    }

  private:
    const NnetChainParallelTrainingOptions opts_;
    bool done_;
    int32 gpu_id_;
    const chain::DenominatorGraph &den_graph_;
    const nnet3::Nnet &nnet_;
    nnet3::Nnet *sub_nnet_;
    std::string examples_rspecifier_;
    std::string nnet_wxfilename_;
    KALDI_DISALLOW_COPY_AND_ASSIGN(NnetChainTrainerThread);
  };

  std::string Replace(const std::string &template_job, const std::string &delim,
                      const std::string &special) {
    std::string special_job = template_job;
    int32 idx = special_job.find(delim);
    KALDI_ASSERT(idx >= 0);
    special_job.replace(idx, delim.size(), special);
    KALDI_LOG << template_job << " -> " << special_job;
    return special_job;
  }

  std::string Replace(const std::string &template_job, const std::string &delim,
                      int32 job_id) {
     std::ostringstream ss;
     ss << job_id;
     return Replace(template_job, delim, ss.str());
  }
}
}

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet3;
    using namespace kaldi::chain;
    typedef kaldi::int32 int32;
    typedef kaldi::int64 int64;

    const char *usage =
    "Train nnet3+chain neural network parameters with backprop and stochastic\n"
    "gradient descent.  Minibatches are to be created by nnet3-chain-merge-egs in\n"
    "the input pipeline.  This training program is single-threaded (best to\n"
    "use it with a GPU).\n"
    "\n"
    "Usage:  nnet3-chain-train [options] <raw-nnet-in> <denominator-fst-in> <chain-training-examples-in> <raw-nnet-out>\n"
    "\n"
    "nnet3-chain-train 1.raw den.fst 'ark:nnet3-merge-egs 1.cegs ark:-|' 2.raw\n";

    std::string gpus_str = "";
    int32 num_nnet_jobs = 0;
    NnetChainParallelTrainingOptions opts;

    ParseOptions po(usage);
    po.Register("num-nnet-jobs", &num_nnet_jobs, "Nnet jobs number");
    opts.Register(&po);

    po.Read(argc, argv);

    if (po.NumArgs() < 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string nnet_rxfilename = po.GetArg(1),
    den_fst_rxfilename = po.GetArg(2),
    nnet_wxfilename = po.GetArg(3);
    KALDI_ASSERT(num_nnet_jobs > 0);

    Nnet nnet;
    ReadKaldiObject(nnet_rxfilename, &nnet);

    KALDI_ASSERT(!gpus_str.empty());
    std::vector<int32> gpus;
    KALDI_ASSERT(SplitStringToIntegers(gpus_str, ",", true, &gpus));

    bool ok = true;

    {
      fst::StdVectorFst den_fst;
      ReadFstKaldi(den_fst_rxfilename, &den_fst);
      chain::DenominatorGraph den_graph = chain::DenominatorGraph(den_fst, nnet.OutputDim("output"));

      TaskSequencerConfig config;
      config.num_threads = gpus.size();
      std::vector<bool> nnet_job_status(gpus.size(), true);

      int32 job_id = 1; // start from 1
      for (int32 i = 4; i <= po.NumArgs();) {
        while (job_id < num_nnet_jobs) {
          TaskSequencer<NnetChainTrainerThread> sequencer(config);
          for (int32 g = 0; g < gpus.size(); g++, i++, job_id++) {
            if (i >= po.NumArgs() || job_id >= num_nnet_jobs) break;
            sequencer.Run(new NnetChainTrainerThread(opts, g, den_graph, nnet, po.GetArg(i),
                          Replace(nnet_wxfilename, "JOB", job_id)));
          }
          if (i >= po.NumArgs()) break;
        }
        // // check job status
        // for (int32 g = 0; g < gpus.size(); g++) {
        //   ok = ok && nnet_job_status[g];
        //   KALDI_ASSERT(nnet_job_status[g]);
        // }
      }
    }

    return (ok ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
               return -1;
  }
}
