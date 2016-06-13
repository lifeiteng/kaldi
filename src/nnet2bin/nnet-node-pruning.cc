// nnet2bin/nnet-node-pruning.cc

// 2014.12 Feiteng 
// Reference paper: RESHAPING DEEP NEURAL NETWORK FOR FAST DECODING BY NODE-PRUNING
// only Output-weights Norm (onorm) and Input-weights Norm (inorm)
// only for Sigmoid Tanh ReLU, not Maxout Pnorm  NonlinearComponents.

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "nnet2/am-nnet.h"
#include "hmm/transition-model.h"
#include "tree/context-dep.h"

#include <algorithm>

namespace kaldi {
namespace nnet2 {

struct NnetNodePruningOpts {
  BaseFloat percent; // 0.0 - 1.0
  BaseFloat threshold; //

  bool onorm;
  bool inorm; 
  bool layer; // cut per layer(when percent >0)
  BaseFloat lambda; //lambda * onorm + (1-lambda) * inorm
  //TODO  inorm 考虑 bias信息 + linear信息

  NnetNodePruningOpts(): percent(-1.0), threshold(-1.0), onorm(false), inorm(false),
            layer(false), lambda(-1.0){ }

  void Register(OptionsItf *po) {
    po->Register("percent", &percent, "the percent of all nodes to be pruned.");
    po->Register("threshold", &threshold, "use this threshold value to prune the nodes.");
    po->Register("onorm", &onorm, "output weights norm.");
    po->Register("inorm", &inorm, "input weights norm.");
    po->Register("per-layer", &layer, "when percent>0, pruning per layer.");
    po->Register("ionorm-lambda", &lambda, " every node weights is computed by lambda * onorm + (1-lambda) * inorm.");
  }  

};

class NnetNodePruning {
public:
    // all work done in construnctor function.
    // 
    NnetNodePruning(const NnetNodePruningOpts& opts, Nnet* nnet)
      :opts_(opts), nnet_(nnet), node_num_(0){
      KALDI_ASSERT(opts_.percent * opts_.threshold < 0);
      KALDI_ASSERT(opts_.onorm != opts_.inorm);
      KALDI_ASSERT(!((opts_.onorm || opts_.inorm) && (opts_.lambda>=0.0)));
      KALDI_ASSERT( opts_.onorm || opts_.inorm || (opts_.lambda>=0.0));
      if (opts_.lambda >= 0.0) 
      KALDI_ASSERT(opts_.lambda <= 1.0);
      KALDI_LOG << "NnetNodePruningOpts& opts value is ok!";
      Pruning();
    }

    ~NnetNodePruning() {
      stats_info_.clear();
      node_cout_idxs_.clear();
    }

private:
    void Pruning() {
      ComputeStatsInfo();
      LabelToPrunedNodes();
      DoPruning();
    }

    void ComputeStatsInfo() {
      for (int32 c = 0; c < nnet_->NumComponents(); ++c) {
        if (dynamic_cast<NonlinearComponent*>(&(nnet_->GetComponent(c))) != NULL) {
          if (c + 1 < nnet_->NumComponents()) {
            // 处理 Softmax AffineTransform SumGroup
            if (c + 2 <= nnet_->NumComponents()) {
              if (nnet_->GetComponent(c + 2).Type() == "SumGroupComponent")
                break;
            }

            if (opts_.onorm) {
              KALDI_LOG << "\n NnetNodePruning - onorm";
              AffineComponent* affine_com = dynamic_cast<AffineComponent*>(&(nnet_->GetComponent(c + 1)));
              if (affine_com != NULL) {
                node_num_ += affine_com->InputDim();
                Vector<BaseFloat> vec(affine_com->InputDim());
                Matrix<BaseFloat>  W(affine_com->LinearParams());
                W.ApplyPowAbs(1.0, false); // abs
                vec.AddRowSumMat(1.0 / W.NumRows(), W, 0.0); //SumRows
                stats_info_.push_back(std::make_pair<>(c, vec));
              }
            }
            else if (opts_.inorm) {
              KALDI_LOG << "\n NnetNodePruning - inorm";
              AffineComponent* affine_com = dynamic_cast<AffineComponent*>(&(nnet_->GetComponent(c - 1)));
              if (affine_com != NULL) {
                node_num_ += affine_com->OutputDim();
                Vector<BaseFloat> vec(affine_com->OutputDim());
                Matrix<BaseFloat>  W(affine_com->LinearParams());
                W.ApplyPowAbs(1.0, false); // abs
                vec.AddColSumMat(1.0 / affine_com->OutputDim(), W, 0.0);
                stats_info_.push_back(std::make_pair<>(c, vec));
              }
            } else {
              KALDI_LOG << "\n NnetNodePruning - lambda * onorm + (1-lambda) * inorm [lambda=" << opts_.lambda << "].";
              AffineComponent* affine_before = dynamic_cast<AffineComponent*>(&(nnet_->GetComponent(c - 1)));
              AffineComponent* affine_after = dynamic_cast<AffineComponent*>(&(nnet_->GetComponent(c + 1)));
              if ((affine_before != NULL) && (affine_after != NULL)) {
                node_num_ += affine_before->OutputDim();

                Vector<BaseFloat> vec(affine_before->OutputDim());
                Matrix<BaseFloat>  W_before(affine_before->LinearParams());
                W_before.ApplyPowAbs(1.0, false); // abs
                vec.AddColSumMat((1.0 - opts_.lambda) / affine_before->OutputDim(), W_before, 0.0);

                Matrix<BaseFloat>  W_after(affine_after->LinearParams());
                W_after.ApplyPowAbs(1.0, false); // abs
                vec.AddRowSumMat(opts_.lambda / affine_after->InputDim(), W_after, 1.0); //SumRows

                stats_info_.push_back(std::make_pair<>(c, vec));
              }
            }
          }
        }
      }
    }

    void LabelToPrunedNodes() {
      node_cout_idxs_.clear();

      BaseFloat thres = opts_.threshold;
      if (!opts_.layer) {
        if (opts_.percent >= 0) {
          std::vector<BaseFloat> all_value;
          for (int32 i = 0; i < stats_info_.size(); ++i) {
            BaseFloat* value = stats_info_[i].second.Data();
            BaseFloat  len = stats_info_[i].second.Dim();
            for (int32 j = 0; j < len; ++j) {
                all_value.push_back(value[j]);
            }
          }
          int32 idx = node_num_ * opts_.percent;
          std::nth_element(all_value.begin(), all_value.begin() + idx, all_value.end());
          thres = *(all_value.begin() + idx);
        }

        KALDI_ASSERT(thres >= 0);

        for (int32 i = 0; i < stats_info_.size(); ++i) {
          node_cout_idxs_.push_back(std::make_pair<>(stats_info_[i].first, std::vector<int32>()));
          BaseFloat* value = stats_info_[i].second.Data();
          int32  len = stats_info_[i].second.Dim();
          // 为防止减去过多node，这里做一个限制，最多减去80%=4/5
          // sort *value
          std::sort(value, value + len - 1);
          BaseFloat thres_cut = std::min(thres, value[len * 4 / 5]);
          for (int32 j = 0; j < len; ++j) {
            if (value[j] < thres_cut) {
              node_cout_idxs_[i].second.push_back(j);
            }
          }
        }
      } else { // opts_.layer == true
        for (int32 i = 0; i < stats_info_.size(); ++i) {
          if (opts_.percent >= 0) {
            int32 dim = nnet_->GetComponent(stats_info_[i].first).InputDim();
            int32 idx = dim * opts_.percent;
            std::nth_element(stats_info_[i].second.Data(), stats_info_[i].second.Data() + idx, stats_info_[i].second.Data() + dim);
            thres = *(stats_info_[i].second.Data() + idx);
          }
          KALDI_ASSERT(thres >= 0);

          node_cout_idxs_.push_back(std::make_pair<>(stats_info_[i].first, std::vector<int32>()));
          BaseFloat* value = stats_info_[i].second.Data();
          int32  len = stats_info_[i].second.Dim();
          // 为防止减去过多node，这里做一个限制，最多减去80%=4/5
          // sort *value
          std::sort(value, value + len - 1);
          BaseFloat thres_cut = std::min(thres, value[len * 4 / 5]);
          for (int32 j = 0; j < len; ++j) {
            if (value[j] < thres_cut) {
              node_cout_idxs_[i].second.push_back(j);
            }
          }
        }
      }
    }

    void DoPruning() {
      KALDI_LOG << "Do Pruning...";
      for (int32 i = 0; i < node_cout_idxs_.size(); ++i) {
        int32 c = node_cout_idxs_[i].first;
        KALDI_LOG << "Components c = " << c;
        std::vector<int32> cut_idx(node_cout_idxs_[i].second);

        AffineComponent* affine_com_before = dynamic_cast<AffineComponent*>(&(nnet_->GetComponent(c - 1)));
        AffineComponent* affine_com_after = dynamic_cast<AffineComponent*>(&(nnet_->GetComponent(c + 1)));
        if (affine_com_before == NULL || affine_com_after == NULL)
            KALDI_ERR << " The layer to prune (onorm)'s before and next Component should be AffineComponent or it's child class.";
        // step 1 修改 NonlinearComponents(c)  的维数
        NonlinearComponent* nonlinear_com = dynamic_cast<NonlinearComponent*>(&(nnet_->GetComponent(c)));
        int32 dim = nonlinear_com->InputDim();  // InputDim() == OutputDim()
        KALDI_ASSERT(nonlinear_com->InputDim() == nonlinear_com->OutputDim());
        int32 to_cut = cut_idx.size();
        if (dim - to_cut <= 0) {
          KALDI_LOG << "WARNING: cut too many nodes at Component: " << c << ", maybe you should set percent smaller or threshold smaller.";
          continue;
        }
        nonlinear_com->SetDim(dim - to_cut);

        // step2 修改 c-1 c+1 AffineTransform的 W bias
        Vector<BaseFloat> bias_params_before(affine_com_before->BiasParams());
        Matrix<BaseFloat> linear_params_before(affine_com_before->LinearParams());

        const Vector<BaseFloat> bias_params_after(affine_com_after->BiasParams());
        Matrix<BaseFloat> linear_params_after(affine_com_after->LinearParams());

        linear_params_after.Transpose(); // 因为Matrix类没有 RemoveCol()方法，这里做个转置，RemoveRow()

        for (int32 j = 0; j < cut_idx.size(); ++j) {
          int32 idx = cut_idx[j];
          bias_params_before.RemoveElement(idx - j);
          linear_params_before.RemoveRow(idx - j);
          linear_params_after.RemoveRow(idx - j);
        }
        affine_com_before->SetParams(bias_params_before, linear_params_before);

        linear_params_after.Transpose(); // 转置回来
        affine_com_after->SetParams(bias_params_after, linear_params_after);
      }
    }
private:
    const NnetNodePruningOpts& opts_;
    Nnet* nnet_;
    int32 node_num_;
    std::vector<std::pair<int32, Vector<BaseFloat> > > stats_info_;
    std::vector< std::pair<int32, std::vector<int32> > > node_cout_idxs_;
};
};
}


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet2;
    typedef kaldi::int32 int32;

    const char *usage =
        "Copy a (cpu-based) neural net and its associated transition model,\n"
        "but modify it to reduce the effective parameter count by node pruning method.\n"
        "\n"
        "Usage:  nnet-node-pruning [options] <nnet-in> <nnet-out>\n"
        "e.g.:\n"
        " nnet-node-pruning 1.mdl 1_limited.mdl\n";
    

    bool binary_write = true;
    NnetNodePruningOpts config;
    
    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");
    config.Register(&po);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string nnet_rxfilename = po.GetArg(1),
        nnet_wxfilename = po.GetArg(2);
    
    TransitionModel trans_model;
    AmNnet am_nnet;
    {
      bool binary;
      Input ki(nnet_rxfilename, &binary);
      trans_model.Read(ki.Stream(), binary);
      am_nnet.Read(ki.Stream(), binary);
    }

    KALDI_LOG << "Before Prune            ----------\n " << am_nnet.Info() ;
    NnetNodePruning pruning(config, &am_nnet.GetNnet());
    KALDI_LOG << "After Pruned info about ----------\n " << am_nnet.Info();
    
    {
      Output ko(nnet_wxfilename, binary_write);
      trans_model.Write(ko.Stream(), binary_write);
      am_nnet.Write(ko.Stream(), binary_write);
    }
    KALDI_LOG << "Printed info about " << nnet_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}
