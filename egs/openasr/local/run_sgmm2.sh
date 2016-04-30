#!/bin/bash

# This script is invoked from ../run.sh
# It contains some SGMM-related scripts that I am breaking out of the main run.sh for clarity.

. cmd.sh

# Note: you might want to try to give the option --spk-dep-weights=false to train_sgmm2.sh;
# this takes out the "symmetric SGMM" part which is not always helpful.
steps/train_ubm.sh --cmd "$train_cmd" \
  400 $data/train $data/lang exp/tri3_ali exp/ubm5_sgmm || exit 1;

steps/train_sgmm2.sh --cmd "$train_cmd" \
  $numLeavesSGMM $numGaussSGMM $data/train $data/lang exp/tri3_ali \
  exp/ubm5_sgmm/final.ubm exp/sgmm2_5a || exit 1;


utils/mkgraph.sh $data/lang_test_ug exp/sgmm2_5a exp/sgmm2_5a/graph_ug
steps/decode_sgmm2.sh --nj $nj --cmd "$decode_cmd" --transform-dir exp/tri3/decode_test_ug \
  exp/sgmm2_5a/graph_ug $data/test exp/sgmm2_5a/decode_test_ug


steps/align_sgmm2.sh --nj $nj --cmd "$train_cmd" --transform-dir exp/tri3_ali \
  --use-graphs true --use-gselect true $data/train $data/lang exp/sgmm2_5a exp/sgmm2_5a_ali || exit 1;
steps/make_denlats_sgmm2.sh --nj $nj --sub-split 1 --cmd "$decode_cmd" --transform-dir exp/tri3_ali \
  $data/train $data/lang exp/sgmm2_5a_ali exp/sgmm2_5a_denlats

steps/train_mmi_sgmm2.sh --cmd "$decode_cmd" --transform-dir exp/tri3_ali --boost 0.1 \
  $data/train $data/lang exp/sgmm2_5a_ali exp/sgmm2_5a_denlats exp/sgmm2_5a_mmi_b0.1

for iter in 1 2 3 4; do
  steps/decode_sgmm2_rescore.sh --cmd "$decode_cmd" --iter $iter \
    --transform-dir exp/tri3/decode_test_ug $data/lang_test_ug $data/test exp/sgmm2_5a/decode_test_ug \
    exp/sgmm2_5a_mmi_b0.1/decode_test_ug_it$iter 
done

steps/train_mmi_sgmm2.sh --cmd "$decode_cmd" --transform-dir exp/tri3_ali --boost 0.1 \
 --update-opts "--cov-min-value=0.9" $data/train $data/lang exp/sgmm2_5a_ali exp/sgmm2_5a_denlats exp/sgmm2_5a_mmi_b0.1_m0.9

for iter in 1 2 3 4; do
  steps/decode_sgmm2_rescore.sh --cmd "$decode_cmd" --iter $iter \
    --transform-dir exp/tri3/decode_test_ug $data/lang_test_ug $data/test exp/sgmm2_5a/decode_test_ug \
    exp/sgmm2_5a_mmi_b0.1_m0.9/decode_test_ug_it$iter
done

