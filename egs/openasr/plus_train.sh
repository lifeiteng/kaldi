
stage=10
train_stage=0

src_dir=exp/chain/tdnn_sp
deep=false
src_iter=3000
start_iter=100

# suffix="_openasr02_1"
# data_dir=data/openasr-02-1

suffix="_openasr02_1"
data_dir=data/openasr-02-1

nj=20
exit_stage=
gpus="0 1 2"
nnet_jobs=3

nnet_jobs_initial=0
nnet_jobs_final=0

pruner_opts="--pruner-perlayer 0 --pruner-times \"\"" # --pruner-perlayer 1 --pruner-times 0.4

egs_opts="--nj 20 --max-shuffle-jobs-run 40"
egs_dir=""

num_epochs=5

initial_effective_lrate=0.0001
final_effective_lrate=0.00001
decode_iters="final"
dir_suffix=""
extra_context=6
splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"
bottleneck_dim=1600
src_vars=
run_train_stage=10
get_egs_stage=0

decode_sets="forum native-readaloud non-native-readaloud"
decode_nj=6

. ./cmd.sh 
. ./path.sh
. ./utils/parse_options.sh

gmm_dir=exp/tri3

src_data_dirs="data/train_sp_min1.55_hires"

src_ali_dirs=exp/tri3_all_ali_min1.55
src_lat_dirs=exp/tri3_all_lats_min1.55

tree_dir=exp/chain/tri3_tree
frame_subsampling_factor=3

ali_dir=exp/tri3${suffix}_ali
lat_dir=exp/tri3${suffix}_lats

combined_ali_dir=exp/tri3_combine_data2000${suffix}_ali
combined_lat_dir=exp/tri3_combine_data2000${suffix}_lats

dir=${src_dir}${suffix}${dir_suffix}

if [ $stage -le 1 ]; then
    echo "$0: preparing directory for speed-perturbed data"
    utils/data/perturb_data_dir_speed_3way.sh $data_dir ${data_dir}_sp
    # do volume-perturbation on the training data prior to extracting hires
    # features; this helps make trained nnets more invariant to test data volume.
    utils/data/perturb_data_dir_volume.sh ${data_dir}_sp || exit 1;

    mfccdir=data/mfcc$suffix
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --cmd "$train_cmd" --nj $nj ${data_dir}_sp exp/make_mfcc/${data_dir}_sp $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh ${data_dir}_sp exp/make_mfcc/${data_dir}_sp $mfccdir || exit 1;
fi

if [ $stage -le 4 ]; then
    (
        sleep 100
        utils/copy_data_dir.sh ${data_dir}_sp ${data_dir}_sp_hires || exit 1;
        mfccdir=data/mfcc${suffix}_hires
        steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" --nj 10 ${data_dir}_sp_hires exp/make_mfcc/${data_dir}_sp_hires $mfccdir || exit 1;
        steps/compute_cmvn_stats.sh ${data_dir}_sp_hires exp/make_mfcc/${data_dir}_sp_hires $mfccdir || exit 1;
    ) &
fi

if [ $stage -le 2 ]; then
  steps/align_fmllr.sh --beam 8 --retry-beam 12 --nj $nj ${data_dir}_sp data/lang $gmm_dir ${ali_dir} || exit 1;
  nj=$(cat ${ali_dir}/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh --nj $nj ${data_dir}_sp data/lang $gmm_dir $lat_dir || exit 1;
fi

if [ $stage -le 5 ]; then
    echo "$0: Combine Data/Ali/Lats"
    utils/data/combine_data.sh --skip-fix true data/train_combine_data2000$suffix ${data_dir}_sp_hires $src_data_dirs || exit 1;
    # utils/data/combine_data.sh --skip-fix true data/train_combine_voxpop_ted$suffix ${data_dir}_hires $src_data_dirs || exit 1;
    # steps/combine_ali_dirs.sh data/train_combine_voxpop_ted$suffix $combined_ali_dir $ali_dir $src_ali_dirs || exit 1;
    steps/combine_lat_dirs.sh data/train_combine_data2000$suffix $combined_lat_dir $lat_dir $src_lat_dirs || exit 1;
fi

mkdir -p $dir

cat > $dir/vars <<EOF
train_data_dir=data/train_combine_data2000$suffix
lat_dir=$combined_lat_dir
EOF

if [ $stage -eq 160926 ]; then
    echo "准备LibriSpeech Data"
    # # wget www.openslr.org/resources/11/librispeech-lexicon.txt 
    # # mv librispeech-lexicon.txt /data/LibriSpeech
    # # format the data as Kaldi data directories
    # sub_datasets=""
    # for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
    #   # use underscore-separated names in data directories.
    #   subdir=data/LibriSpeech/$(echo $part | sed s/-/_/g)
    #   # local/data/librispeech_data_prep.sh /data/LibriSpeech/LibriSpeech/$part $subdir || exit 1;
    #   flag=$(echo $part | cut -d"-" -f1 | awk '{print $1;}')
    #   echo "flag = $flag"
    #   if [ "$flag" = "train" ];then
    #     sub_datasets="$sub_datasets $subdir"
    #   else
    #     echo ""
    #     # utils/copy_data_dir.sh $subdir asr-testsets/eng/LibriSpeech/$(echo $part | sed s/-/_/g) || exit 1;
    #   fi
    # done
    # echo "sub_datasets = $sub_datasets"

    # echo "准备发音词典 data/lang_librispeech"
    # awk '{w=$1; $1=""; gsub(/[0-9]/, "", $0); print tolower(w), $0}' /data/LibriSpeech/librispeech-lexicon.txt | \
    #     awk 'FNR==NR{T[$1]=1;} FNR<NR{if (!($1 in T)) print $0;}' data/local/dict/lexicon_9001_ted.txt - | \
    #     >data/local/dict/lexicon_libri_OOV
    # cat data/local/dict/lexicon_libri_OOV | awk '{for(i=2; i<=NF; i++) print $i;}' | sort -u | \
    #     awk 'FNR==NR{T[$1]=1;} FNR<NR{if (!($1 in T)){print "OOV PHONE! " $0;} else {print "OK " $0;}}' data/lang/phones.txt -
    # cat data/local/dict/lexicon_libri_OOV data/local/dict/lexicon_9001_ted.txt >data/local/dict/lexicon_9001_ted_librispeech.txt

    # local/data/openasr_prepare_dict.sh --data data/LibriSpeech --phoneset 9000 data/local/dict/lexicon_9001_ted_librispeech.txt || exit 1;
    # utils/prepare_lang.sh --share-silence-phones true --num-sil-states 3 --position-dependent-phones false \
    #     data/LibriSpeech/local/dict '!SIL' data/LibriSpeech/local/lang_tmp data/lang_librispeech || exit 1;

    # utils/data/combine_data.sh --skip-fix false data/librispeech_train $sub_datasets || exit 1;
    # cp data/librispeech_train/text tmp/text || exit 1;
    # # awk '{k=$1; $1=""; print k " " tolower($0);}' tmp/text >data/librispeech_train/text
    nj=10
    data_dir=data/librispeech_train
    local/data/clean_trans.py -L -V data/lang_librispeech/words.txt ${data_dir}/text ${data_dir}/text || exit 1;
    utils/fix_data_dir.sh data/librispeech_train || exit 1;

    # steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj $nj $data_dir || exit 1;
    # steps/compute_cmvn_stats.sh $data_dir || exit 1;

    data_dir=${data_dir}
    ali_dir=exp/tri3_librispeech_ali
    lat_dir=exp/tri3_librispeech_lats

    (
        sleep 100
        utils/copy_data_dir.sh ${data_dir} ${data_dir}_hires || exit 1;
        steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" --nj 10 ${data_dir}_hires || exit 1;
        steps/compute_cmvn_stats.sh ${data_dir}_hires || exit 1;
    ) &
    nj=20
    # steps/align_fmllr.sh --beam 8 --retry-beam 12 --nj $nj ${data_dir} data/lang_librispeech $gmm_dir ${ali_dir} || exit 1;
    steps/align_fmllr_lats.sh --nj $nj ${data_dir} data/lang_librispeech $gmm_dir $lat_dir || exit 1;

    wait
    data_dir=data/librispeech_train
    echo "$0: Combine Data/Ali/Lats"
    combined_data=data/train_combine_librispeech_openasr02_2_hires
    combined_lats=exp/tri3_librispeech_openasr02_2_lats

    utils/data/combine_data.sh --skip-fix false $combined_data ${data_dir}_hires data/openasr-02-2_hires || exit 1;
    steps/combine_lat_dirs.sh $combined_data $combined_lats $lat_dir exp/tri3_openasr02_2_lats || exit 1;

    stage=6
    mkdir -p $src_vars/../
cat > $src_vars <<EOF
train_data_dir=$combined_data
lat_dir=$combined_lats
EOF
fi

if [ ! -z $src_vars ];then
    echo "Use vars:"
    cat $src_vars
    cp $src_vars $dir
fi

if [ $stage -le 6 ]; then
    if [ ! -f $dir/egs/.done ];then
        mkdir -p $dir/egs
        bash local/chain/run_tdnn.sh --stage 9 --train-stage -10 --exit-stage 0 --adapt-stage $start_iter --cleanup false \
            --gpus "-1 -1 -1 -1" --nnet-jobs 4 --tree-dir $tree_dir \
            --splice-indexes "$splice_indexes" --bottleneck-dim $bottleneck_dim \
            --get-egs-stage $get_egs_stage --egs-opts "$egs_opts" \
            --egs-context-opts "--egs.chunk-right-context $extra_context --egs.chunk-left-context $extra_context" \
            --num-epochs 2 --common-egs-dir "" --dir $dir || exit 1;
        exit 0;
    fi
    egs_dir=$dir/egs
fi

# if [ $stage -le 8 ]; then
#     if [ ! -f $dir/egs_combine/.done ];then
#         echo "Combine Egs: $src_dir/egs(_combine) + $dir/egs -> $dir/egs_combine"
#         if [ -f $src_dir/egs_combine/.done ];then
#             steps/nnet3/combine_egs.py $src_dir/egs_combine $dir/egs $dir/egs_combine || exit 1
#         else
#             steps/nnet3/combine_egs.py --percent "0.1 1" $src_dir/egs $dir/egs $dir/egs_combine >&$dir/egs_combine.log || exit 1;
#         fi
#     else
#         echo "Egs exist at: $dir/egs_combine"
#     fi
#     egs_dir=$dir/egs_combine
# fi

# # exit 0;

if [ ! -d $egs_dir ];then
    echo "No egs."
    exit 1;
fi

# bash copy_train_dir.sh --iter $src_iter --deep $deep --start-iter $start_iter $src_dir $dir || exit 1;
# bash copy_train_dir.sh --deep true --iter $start_iter --start-iter xx \
#     exp/chain/tdnn_sp_openasr02_1_sp_combined_DATA2000 $dir || exit 1;
# rm -f $dir/xx.mdl


if [ $stage -le 10 ]; then
    if [ $nnet_jobs_initial -eq 0 ];then
        nnet_jobs_initial=$nnet_jobs
    fi
    if [ $nnet_jobs_final -eq 0 ];then
        nnet_jobs_final=$nnet_jobs
    fi

    bash local/chain/run_tdnn.sh --stage $run_train_stage --train-stage $train_stage --exit-stage "$exit_stage" \
        --splice-indexes "$splice_indexes" --bottleneck-dim $bottleneck_dim \
        --adapt-stage $start_iter --cleanup true --mini-batch 128 \
        --gpus "$gpus" --nnet-jobs-initial  $nnet_jobs_initial --nnet-jobs-final $nnet_jobs_final \
        --tree-dir $tree_dir --frame-subsampling-factor 3 $pruner_opts \
        --initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate \
        --extra-egs-dirs "" --get-egs-stage 0 --num-epochs $num_epochs --common-egs-dir "$egs_dir" --dir $dir || exit 1;
fi

echo "496666" | sudo -S nvidia-smi -c 0
cmvn_scp=data/train_sp_min1.55_hires/cmvn.scp.sub10k

graph_dir=exp/chain/tdnn/graph_tg

for ddir in $dir;do
    for diter in $decode_iters;do
        for dset in $decode_sets;do
            bash local/decode/online_decode.sh --decode-nj $decode_nj --graph-dir $graph_dir \
                --data asr-testsets/eng --decode-iter $diter \
                --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires_decode.conf"  \
                --decode-suffix "_peruser" --chain true --scoring-opts "--min-lmwt 5 " \
                --decode-sets "$dset" --decode-opts "--stage 0" \
                $ddir &
            sleep 50
        done
        wait
    done
done

echo "$0: DONE!"

exit 0;

