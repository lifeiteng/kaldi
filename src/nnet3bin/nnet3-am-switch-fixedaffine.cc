// nnet3bin/nnet3-am-switch-fixaffine.cc

// Copyright 2016 Feiteng

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
        "Switch AffineComponent in nnet3 neural network to FixedAffineComponent\n"
        "\n"
        "Usage:  nnet3-am-switch-fixedaffine [options] <component-names> <nnet-in> <nnet-out>\n"
        "e.g.:\n"
        " nnet3-am-switch-fixedaffine --binary=false Tdnn_1_affine;Tdnn_2_affine;Tdnn_3_affine 0.mdl fix.mdl\n";

    bool binary_write = true;
    
    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string affine_names_str = po.GetArg(1),
        nnet_rxfilename = po.GetArg(2),
        nnet_wxfilename = po.GetArg(3);

    TransitionModel trans_model;
    AmNnetSimple am_nnet;
    {
      bool binary;
      Input ki(nnet_rxfilename, &binary);
      trans_model.Read(ki.Stream(), binary);
      am_nnet.Read(ki.Stream(), binary);
    }
    std::vector<std::string> affine_names;
    SplitStringToVector(affine_names_str, ";", true, &affine_names);
    KALDI_LOG << "Before Switch: " << am_nnet.GetNnet().Info();
    am_nnet.GetNnet().SwitchToFixedAffine(affine_names);
    KALDI_LOG << "After Switch: " << am_nnet.GetNnet().Info();

    Output ko(nnet_wxfilename, binary_write);
    trans_model.Write(ko.Stream(), binary_write);
    am_nnet.Write(ko.Stream(), binary_write);

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}
