#!/bin/bash
. ./cmd.sh

steps/make_denlats.sh --nj $nj --sub-split 1 --cmd "$train_cmd" \
  --transform-dir exp/tri3 \
  $data/train $data/lang exp/tri3 exp/tri3_denlats || exit 1;

steps/train_mmi.sh --cmd "$train_cmd" --boost 0.1 \
  $data/train $data/lang exp/tri3_ali exp/tri3_denlats exp/tri3_mmi_b0.1  || exit 1;

steps/decode.sh --nj $nj --cmd "$decode_cmd" --transform-dir exp/tri3/decode_test_ug \
  exp/tri3/graph_ug $data/test exp/tri3_mmi_b0.1/decode_test_ug

#first, train UBM for fMMI experiments.
steps/train_diag_ubm.sh --silence-weight 0.5 --nj $nj --cmd "$train_cmd" \
  600 $data/train $data/lang exp/tri3_ali exp/dubm4b

# Next, fMMI+MMI.
steps/train_mmi_fmmi.sh \
  --boost 0.1 --cmd "$train_cmd" $data/train $data/lang exp/tri3_ali exp/dubm4b exp/tri3_denlats \
  exp/tri3_fmmi_a || exit 1;

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj $nj  --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3/decode_test_ug exp/tri3/graph_ug $data/test \
  exp/tri3_fmmi_a/decode_test_ug_it$iter
done

# decode the last iter with the bd model.
for iter in 8; do
 steps/decode_fmmi.sh --nj $nj  --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3/decode_test_ug exp/tri3/graph_ug $data/test \
  exp/tri3_fmmi_a/decode_test_ug_it$iter
done

# fMMI + mmi with indirect differential.
steps/train_mmi_fmmi_indirect.sh \
  --boost 0.1 --cmd "$train_cmd" $data/train $data/lang exp/tri3_ali exp/dubm4b exp/tri3_denlats \
  exp/tri3_fmmi_indirect || exit 1;

for iter in 3 4 5 6 7 8; do
 steps/decode_fmmi.sh --nj $nj  --cmd "$decode_cmd" --iter $iter \
   --transform-dir exp/tri3/decode_test_ug exp/tri3/graph_ug $data/test \
  exp/tri3_fmmi_indirect/decode_test_ug_it$iter
done

