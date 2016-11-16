
stage=10
train_stage=0

egs_dir=""

nj=20

src_iter="1200"
start_iter=100
exit_stage=""

num_epochs=2

gpus="-1 -1 -1 -1"
num_gpus=4

initial_effective_lrate=0.001
final_effective_lrate=0.00001

# fixstr="Tdnn_1_affine;Tdnn_2_affine;Tdnn_3_affine;Tdnn_4_affine"
# suffix="_Fix1234Affine"

# # fixstr="Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
# # suffix="_sp_adapt_telis1_FixAffine_012345"

fixstr="Tdnn_4_affine;Tdnn_5_affine;Tdnn_6_affine;Tdnn_7_affine;Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
suffix="_Fix4567Affine"

decode_iters="final"
graph_dir=../openasr/exp/chain/tdnn/graph_tg
decode_sets="cet_test non-native-readaloud" #"cet_test telis2-asr-test-data"

dir=""

. ./cmd.sh 
. ./path.sh
. ./utils/parse_options.sh

# set -o

gmm_dir=../openasr/exp/tri3
lat_dir=exp/tri3_cet_train_sp_lats


src_dir=../openasr/exp/chain/tdnn_sp_openasr02_1_sp_combined_DATA2000_layer7_smbr_final
tree_dir=../openasr/exp/chain/tri3_tree
frame_subsampling_factor=3

[ -z $dir ] && dir=exp/chain/train_sp_layer7_smbr_adaptive$suffix

if [ $stage -le 0 ]; then
    cd data
    ln -s ../../openasr/data/lang;ln -s ../../openasr/data/lang_biglm_tg
    cd ../
    mkdir -p exp/chain;cd exp/chain; ln -s ../../../openasr/exp/chain/tri3_tree;cd -;
    cd data; ln -s ../../openasr/data_fbank_hires/lang_chain ; cd -;
    mkdir -p local; cd local; ln -s ../../openasr/local/chain; cd -;
fi

data=data
data_dir=data/train_sp

if [ $stage -le 1 ]; then
    # echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
    # utils/data/perturb_data_dir_speed_3way.sh data/train data/train_sp || exit 1;
    # utils/data/perturb_data_dir_volume.sh data/train_sp || exit 1;

    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --cmd "$train_cmd" \
        --nj 4 $data_dir || exit 1;
    steps/compute_cmvn_stats.sh $data_dir || exit 1;
fi

if [ $stage -le 3 ]; then
    steps/align_fmllr_lats.sh --nj $nj $data_dir data/lang $gmm_dir $lat_dir || exit 1;
fi

if [ $stage -le 4 ]; then
    utils/copy_data_dir.sh ${data_dir} ${data_dir}_hires || exit 1;
    steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" --nj $nj \
        ${data_dir}_hires || exit 1;
    steps/compute_cmvn_stats.sh ${data_dir}_hires || exit 1;
fi

mkdir -p $dir

if [ $stage -le 6 ]; then
    lat_dirs=""
    data_dirs=""
    x_flag="train_wave_sp"
    if [ $stage -le 5 ]; then
        # for x in train;do
        # for x in telis openasr_20k;do
        for x in telis openasr_20k train train_wave;do
            # x_flag=$x
            if [ ! -d data/telis ];then
                utils/copy_data_dir.sh asr-trainsets/telis-asr-train-v2/ data/telis
            fi
            if [ ! -d data/train_wave ];then
                utils/copy_data_dir.sh --utt-suffix "_wave" data/train data/train_wave
                rm -f data/train_wave/{feats.scp,cmvn.scp}
                sed -i 's/CET/CET_WAVE/' data/train_wave/wav.scp
                utils/copy_data_dir.sh --utt-suffix "_wave" data/test asr-testsets/eng/cet_test_wave
                sed -i 's/CET/CET_WAVE/' asr-testsets/eng/cet_test_wave/wav.scp
            fi
            if [ ! -d data/${x}_sp ];then
                # rm -r data/train; cp -r data/train_bk data/train;rm -rf data/train_sp;
                if [ -f data/$x/segments ];then
                    awk 'FNR==NR{k=$1; $1=""; T[k]=$0;} FNR<NR{printf("%s sox -t wav %s -t wav - trim %f =%f |\n", $1, T[$2], $3, $4);}' \
                        data/$x/wav.scp data/$x/segments > tmp/wav.scp || exit 1;
                    mv tmp/wav.scp data/$x/wav.scp || exit 1;
                    rm data/$x/segments || exit 1;
                    steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc.conf data/$x || exit 1;
                fi
                utils/data/perturb_data_dir_speed_3way.sh data/$x data/${x}_sp || exit 1;
                utils/data/perturb_data_dir_volume.sh data/${x}_sp || exit 1;
            fi

            lat_dir=exp/tri3_${x}_sp_lats
            data_dir=data/${x}_sp
            if [ ! -f $data_dir/cmvn.scp ];then
                steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc.conf $data_dir || exit 1;
                steps/compute_cmvn_stats.sh $data_dir || exit 1;
            fi

            if [ ! -f $lat_dir/lat.1.gz ];then
                steps/align_fmllr_lats.sh --nj 20 $data_dir data/lang $gmm_dir $lat_dir || exit 1;
            fi

            (
                # sleep 20
                if [ ! -f ${data_dir}_hires/cmvn.scp ];then
                    utils/copy_data_dir.sh $data_dir ${data_dir}_hires || exit 1;
                    steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf ${data_dir}_hires || exit 1;
                    steps/compute_cmvn_stats.sh ${data_dir}_hires || exit 1;
                fi
            ) &

            lat_dirs="$lat_dirs $lat_dir"
            data_dirs="$data_dirs ${data_dir}_hires"
            x=${x}_sp
            mkdir -p tmp
            if [[ "$x" = "train_sp" || "$x" = "train_wave_sp" ]];then
                for snr in -15 -10 -5 0 5 10 15 20 25 30;do
                    dir_suffix="_SNR$snr"
                    if [ ! -f data/$x${dir_suffix}_hires/cmvn.scp ];then
                        rm -rf tmp/$x$dir_suffix
                        local/noise/addnoise.py --snr-db $snr --noise "mixed" --noise-data-dir asr-noisesets/combined/train \
                            --input-data-dir data/$x --output-data-dir tmp/$x$dir_suffix || exit 1;
                        rm -rf data/$x$dir_suffix || exit 1;
                        utils/data/copy_data_dir.sh --utt-suffix "$dir_suffix" tmp/$x$dir_suffix \
                            data/$x${dir_suffix}_hires || exit 1;

                        steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf data/$x${dir_suffix}_hires || exit 1;
                        steps/compute_cmvn_stats.sh data/$x${dir_suffix}_hires || exit 1;
                        rm -rf ${lat_dir}$dir_suffix
                        utils/data/copy_lat_dir.sh --utt-suffix "$dir_suffix" $lat_dir ${lat_dir}$dir_suffix || exit 1;
                    fi

                    data_dirs="$data_dirs data/$x${dir_suffix}_hires"
                    lat_dirs="$lat_dirs ${lat_dir}$dir_suffix"
                done
            else
                dir_suffix="_SNR-5+30"
                if [ ! -f data/$x${dir_suffix}_hires/cmvn.scp ];then
                    rm -rf tmp/$x$dir_suffix
                    local/noise/addnoise.py --snr-db-range \"-5,30\" --noise "mixed" --noise-data-dir asr-noisesets/combined/train \
                        --input-data-dir data/$x --output-data-dir tmp/$x$dir_suffix || exit 1;
                    rm -rf data/$x$dir_suffix || exit 1;
                    utils/data/copy_data_dir.sh --utt-suffix "$dir_suffix" tmp/$x$dir_suffix \
                        data/$x${dir_suffix}_hires || exit 1;

                    steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf data/$x${dir_suffix}_hires || exit 1;
                    steps/compute_cmvn_stats.sh data/$x${dir_suffix}_hires || exit 1;
                    rm -rf ${lat_dir}$dir_suffix
                    utils/data/copy_lat_dir.sh --utt-suffix "$dir_suffix" $lat_dir ${lat_dir}$dir_suffix || exit 1;
                fi

                data_dirs="$data_dirs data/$x${dir_suffix}_hires"
                lat_dirs="$lat_dirs ${lat_dir}$dir_suffix"
            fi
            wait
        done
    fi

    if [ "$x_flag" = "train_sp" ];then
        combined_data_dir=data/cet_SNR-5+30_sp_hires
        combined_lats_dir=exp/tri3_cet_SNR-5+30_sp_lats
    elif [ "$x_flag" = "train_wave_sp" ];then
        combined_data_dir=data/WAVE_MP3_cet_telis_openasr_SNR-15+30_sp_hires
        combined_lats_dir=exp/tri3_WAVE_MP3_cet_telis_openasr_SNR-15+30_sp_lats
    else
        data_dirs="$data_dirs data/cet_SNR-5+30_sp_hires"
        lat_dirs="$lat_dirs exp/tri3_cet_SNR-5+30_sp_lats"
        combined_data_dir=data/cet_telis_openasr_SNR-5+30_sp_hires
        combined_lats_dir=exp/tri3_cet_telis_openasr_SNR-5+30_sp_lats
    fi

    if [ $stage -le 5 ]; then
        echo "DATA = $data_dirs"
        echo "LATS = $lat_dirs"
        sleep 10
        rm -rf $combined_data_dir $combined_lats_dir
        utils/data/combine_data.sh --skip-fix false $combined_data_dir $data_dirs || exit 1;
        utils/fix_data_dir.sh $combined_data_dir || exit 1;
        steps/combine_lat_dirs.sh $combined_data_dir $combined_lats_dir $lat_dirs || exit 1;
    fi

    cat > $dir/vars <<EOF
train_data_dir=$combined_data_dir
lat_dir=$combined_lats_dir
EOF
fi

if [ ! -f $dir/vars ];then
    cat > $dir/vars <<EOF
train_data_dir=${data_dir}_hires
lat_dir=$lat_dir
EOF
fi

cmvn_opts=`cat $src_dir/cmvn_opts` || exit 1;

if [ $stage -le 7 ]; then
    bash copy_train_dir.sh --iter "$src_iter" --deep true --start-iter $start_iter $src_dir $dir || exit 1;
fi

cp $dir/$start_iter.mdl $dir/$start_iter.mdl.bk
if [ $stage -le 7 ]; then
    nnet3-am-switch-fixedaffine "$fixstr" $dir/$start_iter.mdl  $dir/$start_iter.mdl
    sleep 5
fi

if [ $stage -le 8 ]; then
    learn_rates="--initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate"
    echo "496666" | sudo -S nvidia-smi -c 1
    bash local/chain/run_tdnn.sh --stage 12 --exit-stage "$exit_stage" --train-stage $train_stage \
        --adapt-stage $start_iter --cleanup false --gpus "$gpus" --nnet-jobs $num_gpus \
        --suffix $suffix --tree-dir $tree_dir --frame-subsampling-factor $frame_subsampling_factor --cmvn-opts "$cmvn_opts" \
        --pruner-perlayer 0 --pruner-times "" $learn_rates --lang data/lang_chain \
        --get-egs-stage 0 --num-epochs $num_epochs \
        --egs-opts "--nj 10 --max-shuffle-jobs-run 20 --num-utts-subset 20 --frames-per-iter 50000" \
        --egs-context-opts "--egs.chunk-right-context 12 --egs.chunk-left-context 12" \
        --common-egs-dir "$egs_dir" \
        --dir $dir || exit 1;
fi

echo "496666" | sudo -S nvidia-smi -c 0
cmvn_scp=../openasr/data/train_sp_min1.55_hires/cmvn.scp.sub10k

if [ -z $graph_dir ] && [ $stage -le 11 ]; then
  if [ ! -f $dir/final.mdl ]; then
    cp $dir/`echo "$decode_iters" | awk '{print $1}'`.mdl $dir/final.mdl || exit 1;
  fi
  utils/mkgraph.sh --self-loop-scale 1.0 --remove-oov data/lang_biglm_tg $dir $dir/graph_tg
  graph_dir=$dir/graph_tg
fi

for ddir in $dir;do
    for decode_iter in $decode_iters;do
        echo "DIR = $dir  ITER = $decode_iter"
        bash local/decode/online_decode.sh --decode-nj 8 --graph-dir $graph_dir \
            --data asr-testsets/eng --decode-iter $decode_iter \
            --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
            --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
            --decode-suffix "_peruser" --chain true --scoring-opts "--min-lmwt 5 " \
            --decode-sets "$decode_sets" --decode-opts "--stage 0" \
            $ddir || exit 1;
    done
done
echo "496666" | sudo -S nvidia-smi -c 1
