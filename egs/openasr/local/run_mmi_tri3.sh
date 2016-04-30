#!/bin/bash
# Feiteng 2014.12.26
. ./cmd.sh
[ -f path.sh ] && . ./path.sh

train_nj=4
decode_nj=4

# ### align
# steps/align_fmllr.sh --nj "$train_nj" --cmd "$train_cmd" \
#   data/train data/lang exp/tri3 exp/tri3_ali || exit 1;

##修改了words.txt 重新构建HCLG
##utils/mkgraph.sh data/lang_test_bg exp/tri3 exp/tri3/graph_bg

steps/make_denlats.sh --nj "$train_nj" --sub-split 1 --cmd "$train_cmd" \
  --transform-dir exp/tri3_ali data/train data/lang exp/tri3 exp/tri3_denlats || exit 1;

steps/train_mmi.sh --cmd "$train_cmd" --boost 0.1 \
  data/train data/lang exp/tri3 exp/tri3_denlats \
  exp/tri3_mmi_b0.1  || exit 1;

steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" --transform-dir exp/tri3/decode_test_bg \
  exp/tri3/graph_bg data/test exp/tri3_mmi_b0.1/decode_test_bg

###  mmi alignment
steps/align_fmllr.sh --nj "$train_nj" --cmd "$train_cmd" \
  data/train data/lang exp/tri3_mmi_b0.1 exp/tri3_mmi_b0.1_ali || exit 1;


#first, train UBM for fMMI experiments.
steps/train_diag_ubm.sh --silence-weight 0.5 --nj "$train_nj" --cmd "$train_cmd" \
  600 data/train data/lang exp/tri3_ali exp/dubm3

# Next, fMMI+MMI.
steps/train_mmi_fmmi.sh \
  --boost 0.1 --cmd "$train_cmd" data/train data/lang exp/tri3_ali exp/dubm3 exp/tri3_denlats \
  exp/tri3_fmmi_a || exit 1;

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj "$decode_nj"  --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3/decode_test_bg  exp/tri3/graph_bg data/test \
   exp/tri3_fmmi_a/decode_test_bg_it$iter &
done
# # decode the last iter with the bd model.
# for iter in 8; do
#  steps/decode_fmmi.sh --nj "decode_nj"  --cmd "$decode_cmd" --iter $iter \
#    --transform-dir exp/tri3/decode_test_bg  exp/tri3/graph_bg data/test \
#   exp/tri3_fmmi_a/decode_bd_bgpr_dev93_it$iter &
#  steps/decode_fmmi.sh --nj 8  --cmd "$decode_cmd" --iter $iter \
#    --transform-dir exp/tri3b/decode_bd_bgpr_eval92  exp/tri4b/graph_bd_bgpr data/test_eval92 \
#   exp/tri4b_fmmi_a/decode_bgpr_eval92_it$iter &
# done


# fMMI + mmi with indirect differential.
steps/train_mmi_fmmi_indirect.sh \
  --boost 0.1 --cmd "$train_cmd" data/train data/lang exp/tri3_ali exp/dubm3 exp/tri3_denlats \
  exp/tri3_fmmi_indirect || exit 1;

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj "$decode_nj" --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3/decode_test_bg  exp/tri3/graph_bg data/test \
  exp/tri3_fmmi_indirect/decode_test_bg_it$iter &
done

