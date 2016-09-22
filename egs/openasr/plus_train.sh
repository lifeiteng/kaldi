
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
gpus="0 1 2 3"
nnet_jobs=4

pruner_opts="--pruner-perlayer 0 --pruner-times \"\"" # --pruner-perlayer 1 --pruner-times 0.4
splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"

egs_opts="--nj 20 --max-shuffle-jobs-run 40"
egs_dir=""

num_epochs=5

initial_effective_lrate=0.0001
final_effective_lrate=0.00001
decode_iters="final"
dir_suffix=""

quinphone=false
graph_dir=exp/chain/tdnn/graph_tg
decode_nj=5
decode_stage=0
decode_sets="telis2-asr-test-data"  #"forum non-native-readaloud native-readaloud "
run_train_stage=10
bottleneck_dim=1600

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

if ! $quinphone;then
    if [ -z $suffix ];then
        echo "train_data_dir=data/train_combine_data2000_openasr02_1_sp" >$dir/vars
        echo "lat_dir=exp/tri3_combine_data2000_openasr02_1_sp_lats" >>$dir/vars
    else
        echo "train_data_dir=data/train_combine_data2000$suffix" >$dir/vars
        echo "lat_dir=$combined_lat_dir" >>$dir/vars
    fi
else
    echo "train_data_dir=data/train_sp_min1.55_hires" >$dir/vars
    echo "lat_dir=exp/tri3_all_lats_min1.55" >>$dir/vars
fi


run_stage=10
tree_dir_opts="--tree-dir $tree_dir"
tree_suffix=""
tree_context_opts=""
if $quinphone;then
    tree_dir_opts=""
    tree_suffix="--tree-suffix _quinphone"
    tree_context_opts="--context-width=5 --central-position=2"
    run_stage=9
fi

if [ $stage -le 6 ]; then
    if [ ! -f $dir/egs/.done ];then
        mkdir -p $dir/egs
        bash local/chain/run_tdnn.sh --stage $run_stage --train-stage -10 --exit-stage 0 --adapt-stage $start_iter --cleanup false \
            --gpus "-1 -1 -1 -1" --nnet-jobs 4 $tree_dir_opts $tree_suffix --tree-context-opts "$tree_context_opts" \
            --get-egs-stage 0 --egs-opts "$egs_opts" --egs-context-opts "--egs.chunk-right-context 6 --egs.chunk-left-context 6" \
            --num-epochs 2 --common-egs-dir "" --dir $dir || exit 1;
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
    exit 0;
fi

if ! $quinphone;then
    bash copy_train_dir.sh --iter $src_iter --deep $deep --start-iter $start_iter $src_dir $dir || exit 1;
    basedir="exp/chain/tdnn_sp_openasr02_1_sp_combined_DATA2000"
    if [ "$dir" == "$basedir" ];then
        echo "skip copy the same dirs."
    else
        if ! $deep;then
            bash copy_train_dir.sh --deep true --iter $start_iter --start-iter xx \
                $basedir $dir || exit 1;
        fi
    fi
    rm -f $dir/xx.mdl
fi

if [ $stage -le 10 ]; then
    bash local/chain/run_tdnn.sh \
        --splice-indexes "$splice_indexes" \
        --stage $run_train_stage --train-stage $train_stage --exit-stage "$exit_stage" \
        --adapt-stage $start_iter --cleanup true --mini-batch 128 \
        --bottleneck-dim $bottleneck_dim \
        --gpus "$gpus" --nnet-jobs $nnet_jobs $tree_dir_opts $tree_suffix --tree-context-opts "$tree_context_opts" \
        --frame-subsampling-factor 3 $pruner_opts \
        --initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate \
        --extra-egs-dirs "" --get-egs-stage 0 --num-epochs $num_epochs --common-egs-dir "$egs_dir" --dir $dir || exit 1;
fi

# echo "496666" | sudo -S nvidia-smi -c 0
cmvn_scp=data/train_sp_min1.55_hires/cmvn.scp.sub10k

for ddir in $dir;do
    for diter in $decode_iters;do
        for dset in $decode_sets;do
            bash local/decode/online_decode.sh --decode-nj $decode_nj --graph-dir $graph_dir \
                --data asr-testsets/eng --decode-iter $diter \
                --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires_decode.conf"  \
                --decode-suffix "_peruser" --chain true --scoring-opts "--min-lmwt 5 " \
                --decode-sets "$dset" --decode-opts "--stage $decode_stage" \
                $ddir
            sleep 50
        done
        wait
    done
done

echo "$0: DONE!"

exit 0;

