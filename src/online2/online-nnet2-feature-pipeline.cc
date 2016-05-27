// online2/online-nnet2-feature-pipeline.cc

// Copyright    2013  Johns Hopkins University (author: Daniel Povey)

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

#include "online2/online-nnet2-feature-pipeline.h"
#include "transform/cmvn.h"

namespace kaldi {

OnlineNnet2FeaturePipelineInfo::OnlineNnet2FeaturePipelineInfo(
    const OnlineNnet2FeaturePipelineConfig &config):
    silence_weighting_config(config.silence_weighting_config) {
  if (config.feature_type == "mfcc" || config.feature_type == "plp" ||
      config.feature_type == "fbank") {
    feature_type = config.feature_type;
  } else {
    KALDI_ERR << "Invalid feature type: " << config.feature_type << ". "
              << "Supported feature types: mfcc, plp.";
  }

  if (config.mfcc_config != "") {
    ReadConfigFromFile(config.mfcc_config, &mfcc_opts);
    if (feature_type != "mfcc")
      KALDI_WARN << "--mfcc-config option has no effect "
                 << "since feature type is set to " << feature_type << ".";
  }  // else use the defaults.

  if (config.plp_config != "") {
    ReadConfigFromFile(config.plp_config, &plp_opts);
    if (feature_type != "plp")
      KALDI_WARN << "--plp-config option has no effect "
                 << "since feature type is set to " << feature_type << ".";
  }  // else use the defaults.

  if (config.fbank_config != "") {
    ReadConfigFromFile(config.fbank_config, &fbank_opts);
    if (feature_type != "fbank")
      KALDI_WARN << "--fbank-config option has no effect "
                 << "since feature type is set to " << feature_type << ".";
  }  // else use the defaults.

  use_cmvn = false;
  if (config.online_cmvn_config != "") {
    use_cmvn = true;
    KALDI_LOG(2) << "Read cmvn config.";
    ReadConfigFromFile(config.online_cmvn_config, &cmvn_opts);
    global_cmvn_stats_rxfilename = config.global_cmvn_stats_rxfilename;
    if (global_cmvn_stats_rxfilename == "")
      KALDI_ERR << "--global-cmvn-stats option is required.";
  }  // else use the defaults.

  add_pitch = config.add_pitch;
  
  if (config.online_pitch_config != "") {
    ReadConfigsFromFile(config.online_pitch_config,
                        &pitch_opts,
                        &pitch_process_opts);
    if (!add_pitch)
      KALDI_WARN << "--online-pitch-config option has no effect "
                 << "since you did not supply --add-pitch option.";
  }  // else use the defaults.

  if (config.ivector_extraction_config != "") {
    use_ivectors = true;
    OnlineIvectorExtractionConfig ivector_extraction_opts;
    ReadConfigFromFile(config.ivector_extraction_config,
                       &ivector_extraction_opts);
    ivector_extractor_info.Init(ivector_extraction_opts);
  } else {
    use_ivectors = false;
  }
}

OnlineNnet2FeaturePipeline::OnlineNnet2FeaturePipeline(
    const OnlineNnet2FeaturePipelineInfo &info):
    info_(info) {
  if (info_.feature_type == "mfcc") {
    base_feature_ = new OnlineMfcc(info_.mfcc_opts);
  } else if (info_.feature_type == "plp") {
    base_feature_ = new OnlinePlp(info_.plp_opts);
  } else if (info_.feature_type == "fbank") {
    base_feature_ = new OnlineFbank(info_.fbank_opts);
  } else {
    KALDI_ERR << "Code error: invalid feature type " << info_.feature_type;
  }

  {
    cmvn_ = NULL;
    if (info_.use_cmvn) {
      KALDI_LOG(2) << "Using cmvn feature.";
      KALDI_ASSERT(info_.global_cmvn_stats_rxfilename != "");
      ReadKaldiObject(info_.global_cmvn_stats_rxfilename,
                      &global_cmvn_stats_);
      KALDI_ASSERT(global_cmvn_stats_.NumRows() != 0);
      int32 global_dim = global_cmvn_stats_.NumCols() - 1;
      int32 dim = base_feature_->Dim();
      KALDI_ASSERT(global_dim >= dim);
      if (global_dim > dim) {
        Matrix<BaseFloat> last_col(global_cmvn_stats_.ColRange(global_dim, 1));
        global_cmvn_stats_.Resize(global_cmvn_stats_.NumRows(), dim + 1,
                                  kCopyData);
        global_cmvn_stats_.ColRange(dim, 1).CopyFromMat(last_col);
      }
      Matrix<double> global_cmvn_stats_dbl(global_cmvn_stats_);
      OnlineCmvnState initial_state(global_cmvn_stats_dbl);
      cmvn_ = new OnlineCmvn(info_.cmvn_opts, initial_state, base_feature_);
      feature_ = cmvn_;
    } else {
      feature_ = base_feature_;
    }
  }

  if (info_.add_pitch) {
    pitch_ = new OnlinePitchFeature(info_.pitch_opts);
    pitch_feature_ = new OnlineProcessPitch(info_.pitch_process_opts,
                                            pitch_);
    feature_plus_optional_pitch_ = new OnlineAppendFeature(feature_,
                                                         pitch_feature_);
  } else {
    pitch_ = NULL;
    pitch_feature_ = NULL;
    feature_plus_optional_pitch_ = feature_;
  }

  if (info_.use_ivectors) {
    ivector_feature_ = new OnlineIvectorFeature(info_.ivector_extractor_info,
                                                base_feature_);
    final_feature_ = new OnlineAppendFeature(feature_plus_optional_pitch_,
                                             ivector_feature_);
  } else {
    ivector_feature_ = NULL;
    final_feature_ = feature_plus_optional_pitch_;
  }
  dim_ = final_feature_->Dim();
}

int32 OnlineNnet2FeaturePipeline::Dim() const { return dim_; }

bool OnlineNnet2FeaturePipeline::IsLastFrame(int32 frame) const {
  return final_feature_->IsLastFrame(frame);
}

int32 OnlineNnet2FeaturePipeline::NumFramesReady() const {
  return final_feature_->NumFramesReady();
}

void OnlineNnet2FeaturePipeline::GetFrame(int32 frame,
                                          VectorBase<BaseFloat> *feat) {
  return final_feature_->GetFrame(frame, feat);
}

void OnlineNnet2FeaturePipeline::SetCmvnState(const OnlineCmvnState &cmvn_state) {
  if (cmvn_)
    cmvn_->SetState(cmvn_state);
  else
    KALDI_WARN << "Not use cmvn!";
}

void OnlineNnet2FeaturePipeline::GetCmvnState(OnlineCmvnState *cmvn_state) {
  if (cmvn_) {
    int32 frame = cmvn_->NumFramesReady() - 1;
    // the following call will crash if no frames are ready.
    cmvn_->GetState(frame, cmvn_state);
  } else
    KALDI_WARN << "Not use cmvn!";
}

void OnlineNnet2FeaturePipeline::SetAdaptationState(
    const OnlineIvectorExtractorAdaptationState &adaptation_state) {
  if (info_.use_ivectors) {
    ivector_feature_->SetAdaptationState(adaptation_state);
  }
  // else silently do nothing, as there is nothing to do.
}

void OnlineNnet2FeaturePipeline::GetAdaptationState(
    OnlineIvectorExtractorAdaptationState *adaptation_state) const {
  if (info_.use_ivectors) {
    ivector_feature_->GetAdaptationState(adaptation_state);
  }
  // else silently do nothing, as there is nothing to do.
}


OnlineNnet2FeaturePipeline::~OnlineNnet2FeaturePipeline() {
  // Note: the delete command only deletes pointers that are non-NULL.  Not all
  // of the pointers below will be non-NULL.
  // Some of the online-feature pointers are just copies of other pointers,
  // and we do have to avoid deleting them in those cases.
  if (final_feature_ != feature_plus_optional_pitch_)
    delete final_feature_;
  delete ivector_feature_;
  if (feature_plus_optional_pitch_ != feature_)
    delete feature_plus_optional_pitch_;
  delete pitch_feature_;
  delete pitch_;
  delete cmvn_;
  delete base_feature_;
}

void OnlineNnet2FeaturePipeline::AcceptWaveform(
    BaseFloat sampling_rate,
    const VectorBase<BaseFloat> &waveform) {
  base_feature_->AcceptWaveform(sampling_rate, waveform);
  if (pitch_)
    pitch_->AcceptWaveform(sampling_rate, waveform);
}

void OnlineNnet2FeaturePipeline::UpdateFrameWeights(
    const std::vector<std::pair<int32, BaseFloat> > &delta_weights) {
  if (ivector_feature_ != NULL)
    ivector_feature_->UpdateFrameWeights(delta_weights);
}

void OnlineNnet2FeaturePipeline::InputFinished() {
  base_feature_->InputFinished();
  if (pitch_)
    pitch_->InputFinished();
}

BaseFloat OnlineNnet2FeaturePipelineInfo::FrameShiftInSeconds() const {
  if (feature_type == "mfcc") {
    return mfcc_opts.frame_opts.frame_shift_ms * 1.0e-03;
  } else if (feature_type == "plp") {
    return plp_opts.frame_opts.frame_shift_ms * 1.0e-03;
  } else {
    KALDI_ERR << "Unknown feature type " << feature_type;
    return 0.0;
  }
}


}  // namespace kaldi
