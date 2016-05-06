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

numLeavesMLLTb=6000
numGaussMLLTb=120000

numLeavesSAT=4000
numGaussSAT=90000

feats_nj=6
train_nj=6
decode_nj=2
nj=12

data=data

if [ $stage -le -2 ];then
    echo ============================================================================
    echo "                Data & Lexicon & Language Preparation                     "
    echo ============================================================================
    echo "======== 处理数据集 voxpop TED openasr-data-01 ========"
    # local/std_prepare_data.sh --train true --test true --corpus "voxpop" --data data/voxpop /data/voxpop
    # (
    #     ted=/home/feiteng/kaldi-trunk/egs/tedlium/s5/data
    #     mkdir -p data/tedlium
    #     cp -r $ted/{train,test,dev} data/tedlium
    #     for x in train test dev;do
    #         # [ ! -f data/tedlium/$x/text.back ] && cp data/tedlium/$x/text data/tedlium/$x/test.back
    #         awk '{k=$1; $1=""; t=tolower($0); print k, t;}' $ted/$x/text>data/tedlium/$x/text
    #     done
    # )
    # local/std_prepare_data.sh --train true --corpus "openasr" --data data/openasr-01 /data/openasr-data-01 
    
    # # ted=/home/feiteng/kaldi-trunk/egs/tedlium/s5/data
    # (
    #     echo "========  准备发音词典  ========"
    #     rm -rf data/local/dict
    #     mkdir -p data/local/dict
    #     cat /data/dictionary/{TEDLIUM.150K.dic,9001.dict} >data/local/dict/lexicon_9001_ted.txt
    #     local/std_prepare_dict.sh --data data --phoneset 9000 data/local/dict/lexicon_9001_ted.txt || exit 1;
    # )
    
    # echo "========  准备langs    ========"
    # # Prepare $${lang} and $data/local/lang directories
    # utils/prepare_lang.sh --share-silence-phones true --num-sil-states 3 --position-dependent-phones false \
    #     data/local/dict '!SIL' data/local/lang_tmp data/lang || exit 1;
    # exit 1;

    # echo "========  数据清洗     ========"
    # dict=data/local/dict/lexicon.txt
    # for x in voxpop tedlium openasr-01;do
    #     for y in train test dev;do
    #         [ ! -d data/$x/$y ] && continue
    #         echo "Process data/$x/$y/text..."
    #         # cp data/$x/$y/.backup/text data/$x/$y/text || exit 1;
    #         # wc -l data/$x/$y/text
    #         cp data/$x/$y/text data/$x/$y/text.t
    #         local/clean_trans.py --lower True --clean-oov True $dict data/$x/$y/text.t data/$x/$y/text || exit 1;
    #         # cp data/$x/$y/text.t data/$x/$y/text
    #         utils/fix_data_dir.sh data/$x/$y
    #         echo "======"
    #     done
    # done
    # exit 1;

    # # echo "========  准备语言模型  ========"
    # # local/std_prepare_lm.sh --data data || exit 1;

    # # echo "========  format data ========"
    # local/std_format_data.sh --data data --lm-suffix "translm_tg" data/local/lm/trans_lm_3.arpa || exit 1;
    # local/std_format_data.sh --data data --lm-suffix "biglm_tg" /data/LM/interp_lm.prune-8 || exit 1 &

    # (
    # echo "======== 统计 duration ========"
    # # for x in voxpop tedlium openasr-01;do
    # for x in openasr-01;do
    #     for y in train test dev;do
    #         [ ! -d data/$x/$y ] && continue
    #         local/clean_trans.py data/$x/$y/wav.scp data/$x/$y/wav.scp || exit 1;
    #         utils/fix_data_dir.sh data/$x/$y || exit 1;

    #         utils/data/get_utt2dur.sh data/$x/$y || exit 1;
    #         awk 'BEGIN{sum=0;} {sum+=sprintf("%f",$2)} END{printf("%.3f seconds %.3f hours\n",sum, sum/3600);}' data/$x/$y/utt2dur >data/$x/$y/duration
    #         echo "data/$x/$y `cat data/$x/$y/duration`"
    #     done
    # done
    # ) &

    # # for x in voxpop tedlium openasr-01;do
    # for x in openasr-01;do
    #     for y in train test dev;do
    #         [ ! -d data/$x/$y ] && continue
    #         echo "Process data/$x/$y ..."
    #         # grep -v -f local/users.filter.base64 data/$x/$y/text >tmp/text || exit 1;
    #         # mv tmp/text data/$x/$y/text || exit 1;
    #         utils/fix_data_dir.sh data/$x/$y || exit 1;
    #         echo ============================================================================
    #         echo "        Fbank Feature Extration & CMVN for Training and Test set on"  `date`
    #         echo ============================================================================

    #         featdir=fbank40
    #         steps/make_fbank.sh --nj $nj --cmd "run.pl" data/$x/$y exp/make_feat_${x}_fbank/$y data/$x/$featdir || exit 1;
    #         steps/compute_cmvn_stats.sh data/$x/$y exp/make_feat_${x}_fbank/$y data/$x/$featdir || exit 1;

    #         echo ============================================================================
    #         echo "        MFCC Feature Extration & CMVN for Training and Test set on"  `date`
    #         echo ============================================================================

    #         featdir=mfcc24
    #         steps/make_mfcc.sh --nj $nj --cmd "run.pl" data/$x/$y exp/make_feat_$x_mfcc/$y data/$x/$featdir || exit 1;
    #         steps/compute_cmvn_stats.sh data/$x/$y exp/make_feat_$x_mfcc/$y data/$x/$featdir || exit 1;
    #     done
    # done
   
    # echo "======== 分配数据集 500hours 1500hours ========"
    # for x in voxpop tedlium openasr-01;do
    #     for y in train test dev;do
    #         [ ! -d data/$x/$y ] && continue
    #         echo "Process data/$x/$y ..."
    #         rm -rf data_mfcc/$x/$y
    #         mkdir -p data_mfcc/$x
    #         cp -r data/$x/$y data_mfcc/$x
    #         cat data/$x/mfcc24/raw_mfcc_$y.*.scp >data_mfcc/$x/$y/feats.scp
    #         cat data/$x/mfcc24/cmvn_$y.scp >data_mfcc/$x/$y/cmvn.scp
            
    #         mkdir -p /ssd/data_mfcc/$x
    #         # rm -rf /ssd/data_mfcc/$x/mfcc24
    #         cp -r data/$x/mfcc24 /ssd/data_mfcc/$x
    #         sed -i 's/\/home\/feiteng\/kaldi-trunk\/egs\/openasr\/data/\/ssd\/data_mfcc/g' data_mfcc/$x/$y/feats.scp
    #         sed -i 's/\/home\/feiteng\/kaldi-trunk\/egs\/openasr\/data/\/ssd\/data_mfcc/g' data_mfcc/$x/$y/cmvn.scp

    #         rm -rf data_fbank/$x/$y
    #         mkdir -p data_fbank/$x
    #         cp -r data/$x/$y data_fbank/$x
    #         cat data/$x/fbank40/raw_fbank_$y.*.scp >data_fbank/$x/$y/feats.scp
    #         cat data/$x/fbank40/cmvn_$y.scp >data_fbank/$x/$y/cmvn.scp

    #         mkdir -p /ssd/data_fbank/$x
    #         cp -r data/$x/fbank40 /ssd/data_fbank/$x
    #         # rm -rf /ssd/data_fbank/$x
    #         sed -i 's/\/home\/feiteng\/kaldi-trunk\/egs\/openasr\/data/\/ssd\/data_fbank/g' data_fbank/$x/$y/feats.scp
    #         sed -i 's/\/home\/feiteng\/kaldi-trunk\/egs\/openasr\/data/\/ssd\/data_fbank/g' data_fbank/$x/$y/cmvn.scp
    #     done
    # done

    echo "========  combine data ========"
    # for x in "mfcc" "fbank";do
    #     rm -rf data_$x/train
    #     rm -f data_$x/lang
    #     utils/data/combine_data.sh --skip-fix true data_$x/train data_$x/voxpop/train data_$x/tedlium/train data_$x/openasr-01/train || exit 1;
    #     # utils/fix_data_dir.sh data_$x/train || exit 1;
    #     ln -s data/lang data_$x/lang || exit 1;
    # done

    # dict=data/local/dict/lexicon.txt
    # for x in "mfcc" "fbank";do
    #     rm -rf data_$x/train
    #     for y in voxpop tedlium openasr-01;do
    #         cp data_$x/$y/train/text data_$x/$y/train/text.t
    #         local/clean_trans.py --lower True --clean-oov True $dict data_$x/$y/train/text.t data_$x/$y/train/text || exit 1;
    #         # cp data_$x/$y/train/text.t data_$x/$y/train/text
    #         utils/fix_data_dir.sh data_$x/$y/train || exit 1;
    #     done
    #     utils/data/combine_data.sh --skip-fix true data_$x/train data_$x/voxpop/train data_$x/tedlium/train data_$x/openasr-01/train || exit 1;
    # done
    # exit 1;

    # for x in "mfcc";do
    #     rm -rf data_$x/train_all
    #     mv data_$x/train data_$x/train_all
    #     rm -rf data_$x/train
    #     rm -rf data_$x/openasr-01/train.500k
    #     utils/subset_data_dir.sh data_$x/openasr-01/train 500000 data_$x/openasr-01/train.500k || exit 1;
    #     utils/data/combine_data.sh --skip-fix true data_$x/train data_$x/voxpop/train data_$x/tedlium/train data_$x/openasr-01/train.500k || exit 1;
    #     # rm -rf data_$x/train_all
    #     # utils/data/combine_data.sh --skip-fix true data_$x/train_all data_$x/voxpop/train data_$x/tedlium/train data_$x/openasr-01/train || exit 1;
    # done

    # local/std_format_data.sh --data data --lm-suffix "translm_tg" data/local/lm/trans_lm_3.arpa || exit 1;
    local/std_format_data.sh --data data --lm-suffix "biglm_tg" /data/LM/interp_lm.prune-8 || exit 1 &
fi

data=data_mfcc
lang=data/lang_biglm_tg
graph_dir="graph_`basename $lang`"
decode_dir="decode_test_`basename $lang`"

# [ ! -d $data/lang ] && ln -s data/lang $data/lang 
# [ ! -d $data/test ] && ln -s /llswork1/ASR_testset/eng/Mar-17-2015-forum $data/test

if [ $stage -le 0 ];then
    echo ============================================================================
    echo "                     MonoPhone Training & Decoding             on"  `date`
    echo ============================================================================
    # rm -rf $data/train.50k
    # utils/subset_data_dir.sh $data/train 50000 $data/train.50k || exit 1;
    # utils/fix_data_dir.sh $data/train.50k

    steps/train_mono.sh  --nj "$train_nj" --cmd "$train_cmd" $data/train.50k $data/lang exp/mono
    (
    utils/mkgraph.sh --mono $lang exp/mono exp/mono/${graph_dir}
    steps/decode.sh --config conf/decode.config --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/mono/${graph_dir} $data/test exp/mono/${decode_dir}
    )&
fi


if [ $stage -le 1 ];then
    echo ============================================================================
    echo "           tri1 : Deltas + Delta-Deltas Training & Decoding    on"  `date`
    echo ============================================================================
    # steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" \
    #  $data/train $data/lang exp/mono exp/mono_ali

    # Train tri1, which is deltas + delta-deltas, on train data.
    steps/train_deltas.sh --cmd "$train_cmd" --stage 32 \
     $numLeavesTri1 $numGaussTri1 $data/train $data/lang exp/mono_ali exp/tri1
    (
    utils/mkgraph.sh $lang exp/tri1 exp/tri1/${graph_dir}
    steps/decode.sh --config conf/decode.config --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/tri1/${graph_dir} $data/test exp/tri1/${decode_dir}
    )&
fi


if [ $stage -le 2 ];then
    echo ============================================================================
    echo "                 tri2 : LDA + MLLT Training & Decoding          on"  `date`
    echo ============================================================================

    # steps/align_si.sh --retry-beam 15 --nj "$train_nj" --cmd "$train_cmd" \
    #   $data/train $data/lang exp/tri1 exp/tri1_ali

    steps/train_lda_mllt.sh --cmd "$train_cmd" --stage ${train_stage} \
     --splice-opts "--left-context=3 --right-context=3" \
     $numLeavesMLLT $numGaussMLLT $data/train $data/lang exp/tri1_ali exp/tri2
    (
    utils/mkgraph.sh $lang exp/tri2 exp/tri2/${graph_dir}
    steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/tri2/${graph_dir} $data/test exp/tri2/${decode_dir}
    )&

    # Align tri2 system with train data.
    steps/align_si.sh --retry-beam 12 --nj "$train_nj" --cmd "$train_cmd" \
     --use-graphs false $data/train_all $data/lang exp/tri2 exp/tri2_all_ali
fi


if [ $stage -le 3 ];then
    echo ============================================================================
    echo "                tri2b : LDA + MLLT Training & Decoding          on"  `date`
    echo ============================================================================

    steps/train_lda_mllt.sh --cmd "$train_cmd" \
     --splice-opts "--left-context=3 --right-context=3" \
     $numLeavesMLLTb $numGaussMLLTb $data/train $data/lang exp/tri1_ali exp/tri2b
    (
    utils/mkgraph.sh $lang exp/tri2b exp/tri2b/${graph_dir}
    steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/tri2b/${graph_dir} $data/test exp/tri2b/${decode_dir}
    )&

    # Align tri2 system with train data.
    steps/align_si.sh --retry-beam 12 --nj "$train_nj" --cmd "$train_cmd" \
     --use-graphs false $data/train_all $data/lang exp/tri2b exp/tri2b_all_ali
fi


if [ $stage -le 6 ];then
    echo ============================================================================
    echo "              tri3 : LDA + MLLT + SAT Training & Decoding       on"  `date`
    echo ============================================================================

    # Align tri2 system with train data.
    # ///////////////////////////////// commented by yxf
    #steps/align_si.sh --retry-beam 12 --nj "$train_nj" --cmd "$train_cmd" \
    # --use-graphs true $data/train $data/lang exp/tri2 exp/tri2_ali

    # From tri2 system, train tri3 which is LDA + MLLT + SAT.
    steps/train_sat.sh --cmd "$train_cmd"  --stage 25 \
     $numLeavesSAT $numGaussSAT $data/train $data/lang exp/tri2_ali exp/tri3
    (
    utils/mkgraph.sh $lang exp/tri3 exp/tri3/${graph_dir}
    steps/decode_fmllr.sh --nj "$decode_nj" --cmd "$decode_cmd" \
     exp/tri3/${graph_dir} $data/test exp/tri3/${decode_dir}
    )&

    steps/align_fmllr.sh --retry-beam 12 --nj "$train_nj" --cmd "$train_cmd" \
     $data/train_all $data/lang exp/tri3 exp/tri3_all_ali
fi

# bash RESULTS test

# bash go.sh

if [ $stage -le 8 ];then
    echo ============================================================================
    echo "                tri2b : LDA + MLLT Training & Decoding          on"  `date`
    echo ============================================================================

    # Align tri2 system with train data.
    steps/align_si.sh --careful true --scale-opts "--transition-scale=1.0 --acoustic-scale=1 --self-loop-scale=0.1" \
      --beam 16 --retry-beam 20 --nj "$train_nj" --cmd "$train_cmd" \
      --use-graphs false $data/train_all $data/lang exp/tri2b exp/tri2b_aw1_all_ali
fi

echo ============================================================================
echo "Finished successfully on" `date`
echo ============================================================================

exit 0
