#!/bin/bash

## Feiteng 2015.03.18
#          2016.03.31

stage=100
train_stage=-10

. ./cmd.sh 
. ./path.sh
. ./utils/parse_options.sh
set -e

# Acoustic model parameters
numLeavesTri1=2500
numGaussTri1=40000
numLeavesMLLT=3000
numGaussMLLT=60000
numLeavesSAT=4000
numGaussSAT=90000

feats_nj=6
train_nj=6
decode_nj=6
nj=6

data=data

if [ $stage -le -2 ];then
    echo ============================================================================
    echo "                Data & Lexicon & Language Preparation                     "
    echo ============================================================================
    echo "======== 处理数据集 voxpop TED openasr-data-01 ========"
    local/std_prepare_data.sh --train true --test true --type 1 /data/voxpop --data data/voxpop
    local/std_prepare_data.sh --train true --test true --type 1 /data/TEDLIUM-1 --data data/TED-1
    local/std_prepare_data.sh --train true --test true --type 1 /data/openasr-data-01 --data data/LLS-1
    
    echo "========  数据清洗     ========"
    for dir in train test;do
        cp $data/$dir/text $data/$dir/text.t
        # awk 'FNR==NR{w=$1; Z[w]=1;} FNR<NR{for(i=2;i<=NF;i++){if(!($i in Z)) printf("%s\n", $1);}}'  $dict $data/$dir/text.t | sort | uniq >oov.sent
        # grep -v -f oov.sent $data/$dir/text.t >$data/$dir/text

        std/local/clean_trans.py --lower True --clean-oov True $dict $data/$dir/text.t $data/$dir/text

        # awk 'FNR==NR{w=$1; Z[w]=1;} FNR<NR{for(i=2;i<=NF;i++){if(!($i in Z)) printf("%s\n", $1);}}'  $dict $data/$dir/text
    done

    echo "========  准备发音词典  ========"
    rm -rf data/local/dict
    local/openasr_prepare_dict.sh --data data models/dicts/words_trans.txt || exit 1;
    
    echo "========  准备langs    ========"

    # Prepare $${lang} and $data/local/lang directories
    utils/prepare_lang.sh --share-silence-phones true --num-sil-states 3 --position-dependent-phones false \
        data/local/dict '!SIL' data/local/lang_tmp data/lang || exit 1;
    
    echo "========  准备语言模型  ========"
    local/openasr_prepare_lm.sh --data data --biglm $biglm

    echo "========  format data ========"
    local/openasr_format_data.sh --data data data/local/lm/mixed_tg.arpa

    echo "========  combine data ========"
    utils/combine_data.sh --skip-fix true data/train data/LLS-1/train data/TED-1/train data/voxpop/train
    utils/fix_data_dir.sh $data/train

    echo "======== 分配数据集 500hours 1000hours 2000hours 5000hours 10000hours ========"
fi

echo "TODO cp data/*/{train,test} to data_fbank"

if [ $stage -le -1 ];then
    echo ============================================================================
    echo "        MFCC Feature Extration & CMVN for Training and Test set on"  `date`
    echo ============================================================================

    featdir=mfcc24
    for x in test train; do
      steps/make_mfcc.sh --nj $nj --cmd "run.pl" $data/$x exp/make_feat/$x $data/$featdir
      steps/compute_cmvn_stats.sh $data/$x exp/make_feat/$x $data/$featdir
    done

    echo ============================================================================
    echo "        Fbank Feature Extration & CMVN for Training and Test set on"  `date`
    echo ============================================================================

    featdir=fbank40
    for x in test train; do
      steps/make_fbank.sh --nj $nj --cmd "run.pl" $data/$x exp/make_feat_fbank/$x $data/$featdir
      steps/compute_cmvn_stats.sh $data/$x exp/make_feat/$x $data/$featdir
    done
fi

lang=data/lang_TODO

if [ $stage -le 0 ];then
    echo ============================================================================
    echo "                     MonoPhone Training & Decoding             on"  `date`
    echo ============================================================================
    utils/subset_data_dir.sh $data/train 80000 $data/train.80k || exit 1;
    utils/fix_data_dir.sh $data/train.80k

    steps/train_mono.sh  --nj "$train_nj" --cmd "$train_cmd" $data/train.80k $data/lang exp/mono

    utils/mkgraph.sh --mono $lang exp/mono exp/mono/graph_ug
    steps/decode.sh --config conf/decode.config --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/mono/graph_ug $data/test exp/mono/decode_test_ug
fi


if [ $stage -le 1 ];then
    echo ============================================================================
    echo "           tri1 : Deltas + Delta-Deltas Training & Decoding    on"  `date`
    echo ============================================================================
    steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" \
     $data/train $data/lang exp/mono exp/mono_ali

    # Train tri1, which is deltas + delta-deltas, on train data.
    steps/train_deltas.sh --cmd "$train_cmd" \
     $numLeavesTri1 $numGaussTri1 $data/train $data/lang exp/mono_ali exp/tri1

    utils/mkgraph.sh $lang exp/tri1 exp/tri1/graph_ug
    steps/decode.sh --config conf/decode.config --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/tri1/graph_ug $data/test exp/tri1/decode_test_ug
fi


if [ $stage -le 2 ];then
    echo ============================================================================
    echo "                 tri2 : LDA + MLLT Training & Decoding          on"  `date`
    echo ============================================================================

    steps/align_si.sh --retry-beam 15 --nj "$train_nj" --cmd "$train_cmd" \
      $data/train $data/lang exp/tri1 exp/tri1_ali

    steps/train_lda_mllt.sh --cmd "$train_cmd" \
     --splice-opts "--left-context=3 --right-context=3" \
     $numLeavesMLLT $numGaussMLLT $data/train $data/lang exp/tri1_ali exp/tri2

    utils/mkgraph.sh $lang exp/tri2 exp/tri2/graph_ug
    steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/tri2/graph_ug $data/test exp/tri2/decode_test_ug
    
    bash RESULTS test
fi


if [ $stage -le 3 ];then
    echo ============================================================================
    echo "              tri3 : LDA + MLLT + SAT Training & Decoding       on"  `date`
    echo ============================================================================

    # Align tri2 system with train data.
    steps/align_si.sh --retry-beam 12 --nj "$train_nj" --cmd "$train_cmd" \
     --use-graphs true $data/train $data/lang exp/tri2 exp/tri2_ali

    # From tri2 system, train tri3 which is LDA + MLLT + SAT.
    steps/train_sat.sh --cmd "$train_cmd" \
     $numLeavesSAT $numGaussSAT $data/train $data/lang exp/tri2_ali exp/tri3

    utils/mkgraph.sh $lang exp/tri3 exp/tri3/graph_ug

    steps/decode_fmllr.sh --nj "$train_nj" --cmd "$decode_cmd" \
     exp/tri3/graph_ug $data/test exp/tri3/decode_test_ug 

    steps/align_fmllr.sh --retry-beam 12 --nj "$train_nj" --cmd "$train_cmd" \
     $data/train $data/lang exp/tri3 exp/tri3_ali

fi

bash RESULTS test

echo ============================================================================
echo "Finished successfully on" `date`
echo ============================================================================

exit 0
