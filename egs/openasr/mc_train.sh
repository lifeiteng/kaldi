

suffix=""
start_iter=100
noise="mixed"

noisesets=asr-noisesets/combined/train

egs_dir=""
skip_train=false
skip_decode=false

stage=10
train_stage=10
srcdata=datanoise/trainsets/openasr500
num_epochs=2
exit_stage=
get_egs_stage=0

# gpus="0 1 2 3 4 5 6 7"
# nnet_jobs=8
gpus="0 1 2 3"
nnet_jobs=4

srcdir=exp/chain/tdnn_sp
cleandir=exp/chain/tdnn_sp
src_egs_combine=""
srciter=3000

egs_opts="--nj 10 --max-shuffle-jobs-run 40"
sort_egs_combine=true
percent=""
combine_egs_opts="--sort"

# fixstr="Tdnn_3_affine;Tdnn_4_affine;Tdnn_5_affine;Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
# fixstr="Tdnn_5_affine;Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
# fixstr="Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
fix_layer_opts=""

deep_egs=false
decode_iters="final"
dir=
decode_clean=true
decode_nnv=true

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

chmod +x -R local

splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"

initial_effective_lrate=0.0002
final_effective_lrate=0.00005
tree_dir=exp/chain/tri3_tree

mfccdir=datanoise/trainsets/mfcc_hires

if [ -z $dir ];then
    dir=exp/chain/tdnn_sp_snr-5to30
    mkdir -p $dir
fi

if [[ $stage -le 0 && -z $egs_dir ]];then
    if [ ! -d datanoise/trainsets/openasr1000 ];then
        utils/subset_data_dir.sh data/openasr-01-train_sp_min1.55_hires 1000000 datanoise/trainsets/openasr1000_hires || exit 1;
        utils/subset_data_dir.sh data/openasr-01-train_sp 1000000 datanoise/trainsets/openasr1000 || exit 1;
        utils/fix_data_dir.sh datanoise/trainsets/openasr1000 || exit 1;
        utils/subset_data_dir.sh data/voxpop-train_sp_hires 500000 datanoise/trainsets/voxpop500 || exit 1;
        utils/fix_data_dir.sh datanoise/trainsets/voxpop500 || exit 1;
    fi
    echo "准备NoiseData"
    dir_suffix="_SNR-5to30"
    gmm_dir=exp/tri3

    telis_combined_lat_dir=exp/tri3_lats_TELIS_NOISE_CLEAN$dir_suffix
    telis_combined_data_dir=datanoise/trainsets/TELIS_NOISE_CLEAN$dir_suffix
    if [ $stage -le -1 ];then
        # # scp -r feiteng@192.168.10.231:/home/feiteng/openasr/exp/tri3_telis1_lats exp || exit 1;
        # rm -rf datanoise/trainsets/telis datanoise/trainsets/telis_sp
        # utils/copy_data_dir.sh asr-trainsets/telis-asr-train-v2/ datanoise/trainsets/telis

        # Telis more snr data
        lat_dirs="exp/tri3_telis1_sp_lats"
        data_dirs="datanoise/trainsets/telis_sp"
        # # data SP make_mfcc
        # utils/data/perturb_data_dir_speed_3way.sh datanoise/trainsets/telis datanoise/trainsets/telis_sp
        # utils/data/perturb_data_dir_volume.sh datanoise/trainsets/telis_sp || exit 1;
        x=telis_sp
        if [ $stage -le -2 ]; then
            
            ali_dir=exp/tri3_telis1_sp_ali
            lat_dir=exp/tri3_telis1_sp_lats

            data_dir=datanoise/trainsets/telis_sp_mfcc
            utils/copy_data_dir.sh datanoise/trainsets/telis_sp datanoise/trainsets/telis_sp_mfcc || exit 1;
            steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc.conf $data_dir || exit 1;
            steps/compute_cmvn_stats.sh $data_dir || exit 1;
            # realigning data as the segments would have changed
            steps/align_fmllr.sh --nj 10 $data_dir data/lang $gmm_dir ${ali_dir} || exit 1;
            nj=$(cat ${ali_dir}/num_jobs) || exit 1;
            steps/align_fmllr_lats.sh --nj 10 $data_dir data/lang $gmm_dir $lat_dir || exit 1;
        fi

        for snr in -5 0 5 10 15 20 25 30;do
            dir_suffix="_SNR$snr"
            # rm -rf tmp/$x$dir_suffix
            # local/noise/addnoise.py --snr-db $snr --noise "mixed" --noise-data-dir $noisesets \
            #     --input-data-dir datanoise/trainsets/$x --output-data-dir tmp/$x$dir_suffix || exit 1;
            # rm -rf datanoise/trainsets/$x$dir_suffix || exit 1;
            # utils/data/copy_data_dir.sh --utt-suffix "$dir_suffix" tmp/$x$dir_suffix \
            #     datanoise/trainsets/$x$dir_suffix || exit 1;

            utils/data/copy_lat_dir.sh --utt-suffix "$dir_suffix" exp/tri3_telis1_sp_lats exp/tri3_lats_${x}$dir_suffix || exit 1;

            data_dirs="$data_dirs datanoise/trainsets/$x$dir_suffix"
            lat_dirs="$lat_dirs exp/tri3_lats_${x}$dir_suffix"
        done

        # for x in $data_dirs;do
        #     if [ ! -f $x/cmvn.scp ];then
        #         steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf $x || exit 1;
        #         steps/compute_cmvn_stats.sh $x || exit 1;
        #     fi
        # done

        # utils/data/combine_data.sh --skip-fix true $telis_combined_data_dir $data_dirs || exit 1;
        steps/combine_lat_dirs.sh $telis_combined_data_dir $telis_combined_lat_dir $lat_dirs || exit 1;
    fi
    # exit 0;

    # # # utils/subset_data_dir.sh data/openasr-01-train_sp 1000000 datanoise/trainsets/openasr1000_sp
    # # # utils/subset_data_dir.sh data/voxpop-train_sp 500000 datanoise/trainsets/voxpop500_sp
    # # utils/copy_data_dir.sh data/openasr-01-train_sp datanoise/trainsets/openasr1000_sp || exit 1;
    # utils/copy_data_dir.sh data/voxpop-train_sp datanoise/trainsets/voxpop500_sp || exit 1;
    # for x in openasr1000 voxpop500;do
    #     utils/copy_data_dir.sh tmp/$x$dir_suffix datanoise/trainsets/${x}_hires || exit 1;
    #     cp datanoise/trainsets/${x}_hires/text datanoise/trainsets/${x}_sp || exit 1;
    #     utils/fix_data_dir.sh datanoise/trainsets/${x}_sp || exit 1;

    #     lat_dir=exp/tri3_lats_${x}_hires
    #     steps/align_fmllr_lats.sh --nj 40 datanoise/trainsets/${x}_sp data/lang $gmm_dir $lat_dir || exit 1;
    # done
    # # exit 0;

    combined_lat_dir=exp/tri3_lats_DATA2000_NOISE_CLEAN$dir_suffix
    combined_data_dir=datanoise/trainsets/DATA2000_NOISE_CLEAN$dir_suffix

    # lat_dirs="$telis_combined_lat_dir exp/tri3_lats_openasr1000_sp exp/tri3_lats_voxpop500_sp"
    lat_dirs="$telis_combined_lat_dir exp/tri3_lats_openasr1000_hires exp/tri3_lats_voxpop500_hires"
    data_dirs="$telis_combined_data_dir datanoise/trainsets/openasr1000_hires datanoise/trainsets/voxpop500_hires"
    
    for x in openasr1000 voxpop500;do
        # local/noise/addnoise.py --snr-db-range \"-5,30\" --noise "mixed" --noise-data-dir $noisesets \
        #     --input-data-dir datanoise/trainsets/$x --output-data-dir tmp/$x$dir_suffix || exit 1;
        # utils/data/copy_data_dir.sh --utt-suffix "$dir_suffix" tmp/$x$dir_suffix \
        #     datanoise/trainsets/$x$dir_suffix || exit 1;

        # steps/make_mfcc.sh --nj 10 --mfcc-config conf/mfcc_hires.conf datanoise/trainsets/$x$dir_suffix || exit 1;
        # steps/compute_cmvn_stats.sh datanoise/trainsets/$x$dir_suffix || exit 1;
        # rm -rf exp/tri3_lats_${x}$dir_suffix
        # utils/data/copy_lat_dir.sh --utt-suffix "$dir_suffix" exp/tri3_lats_${x}_hires exp/tri3_lats_${x}$dir_suffix || exit 1;
        data_dirs="$data_dirs datanoise/trainsets/$x$dir_suffix"
        lat_dirs="$lat_dirs exp/tri3_lats_${x}$dir_suffix"
    done

    utils/data/combine_data.sh --skip-fix false $combined_data_dir $data_dirs || exit 1;
    # steps/combine_lat_dirs.sh $combined_data_dir $combined_lat_dir $lat_dirs || exit 1;

    echo "train_data_dir=${combined_data_dir}" >$dir/vars
    echo "lat_dir=${combined_lat_dir}" >>$dir/vars
fi

if [ $stage -le 1 ];then
    bash copy_train_dir.sh --fix-layer "$fix_layer_opts" --iter $srciter --start-iter $start_iter $srcdir $dir
fi

if [[ $stage -le 10 && ! -f $dir/final.mdl ]];then
    bash local/chain/run_tdnn.sh --stage 10 --train-stage $train_stage --exit-stage "$exit_stage" \
        --adapt-stage $start_iter --cleanup true \
        --gpus "$gpus" --nnet-jobs $nnet_jobs --tree-dir $tree_dir \
        --frame-subsampling-factor 3 --pruner-perlayer 0 --pruner-times "" \
        --initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate \
        --extra-egs-dirs "" --get-egs-stage $get_egs_stage --egs-opts "$egs_opts" \
        --egs-context-opts "--egs.chunk-right-context 6 --egs.chunk-left-context 6" \
        --num-epochs $num_epochs --common-egs-dir "$egs_dir" --dir $dir || exit 1;
fi

# echo "496666" | sudo -S nvidia-smi -c 0
cmvn_scp=data/train_sp_min1.55_hires/cmvn.scp.sub10k
# sort -r $data/$train/cmvn.scp | head -n 10000 >$cmvn_scp
graph_dir=exp/chain/tdnn/graph_tg

echo "496666" | sudo -S nvidia-smi -c 0

if ! $skip_decode;then
    (
        for snr in 0 10 20 30;do
            snr_sets="telis2-asr-test-data-snr$snr"
            decode_nj=8
            if $decode_nnv;then
                decode_nj=4
                snr_sets="$snr_sets Jan-09-2015-nnv-readaloud-snr$snr "
            fi
            for decode_iter in $decode_iters;do
                bash local/decode/online_decode.sh --decode-nj $decode_nj --graph-dir $graph_dir \
                    --data asr-testsets/eng --decode-iter $decode_iter \
                    --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                    --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires_decode.conf"  \
                    --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
                    --decode-sets "$snr_sets" --decode-opts "--stage 0" \
                    $dir &
            done
            sleep 50
        done

        if $decode_clean;then
            decode_sets="Jan-09-2015-nnv-readaloud telis2-asr-test-data"
            for decode_iter in $decode_iters;do
                bash local/decode/online_decode.sh --decode-nj 4 --graph-dir $graph_dir \
                    --data asr-testsets/eng --decode-iter $decode_iter \
                    --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                    --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires_decode.conf"  \
                    --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
                    --decode-sets "$decode_sets" --decode-opts "--stage 0" \
                    $dir &
            done
        fi
        wait
    )
    echo "Decode DONE!"
fi


echo "$0: DONE!"

exit 0;

