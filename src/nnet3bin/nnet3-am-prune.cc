// nnet3bin/nnet3-am-copy.cc

// Copyright 2012-2015  Johns Hopkins University (author:  Daniel Povey)
//           2016 Daniel Galvez

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

#include <typeinfo>
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "hmm/transition-model.h"
#include "nnet3/am-nnet-simple.h"
#include "nnet3/nnet-utils.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet3;
    typedef kaldi::int32 int32;

    const char *usage =
        "Prune nnet3 neural-net acoustic model file; supports conversion\n"
        "to raw model (--raw=true).\n"
        "Usage:  nnet3-am-prune [options] <nnet-in> <nnet-out>\n"
        "e.g.:\n"
        " nnet-am-prune --binary=false 1.mdl text.mdl\n"
        " nnet-am-prune --raw=true 1.mdl 1.raw\n";

    bool binary_write = false,
        raw = false;
    NnetNeuralPruneOpts prune_opts;

    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("raw", &raw, "If true, write only 'raw' neural net "
                "without transition model and priors.");
    prune_opts.Register(&po);
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string nnet_rxfilename = po.GetArg(1),
        nnet_wxfilename = po.GetArg(2);

    TransitionModel trans_model;
    AmNnetSimple am_nnet;
    {
      bool binary;
      Input ki(nnet_rxfilename, &binary);
      trans_model.Read(ki.Stream(), binary);
      am_nnet.Read(ki.Stream(), binary);
    }

    std::cout << "Before prune, Nnet info: " << am_nnet.GetNnet().Info();
    am_nnet.GetNnet().Prune(prune_opts);
    std::cout << "After  prune, Nnet info: " << am_nnet.GetNnet().Info();

    if (raw) {
      WriteKaldiObject(am_nnet.GetNnet(), nnet_wxfilename, binary_write);
      KALDI_LOG << "Copied neural net from " << nnet_rxfilename
                << " to raw format as " << nnet_wxfilename;
    } else {
      Output ko(nnet_wxfilename, binary_write);
      trans_model.Write(ko.Stream(), binary_write);
      am_nnet.Write(ko.Stream(), binary_write);
      KALDI_LOG << "Copied neural net from " << nnet_rxfilename
                << " to " << nnet_wxfilename;
    }
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}
