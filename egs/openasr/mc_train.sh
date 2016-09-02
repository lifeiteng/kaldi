

suffix=""
start_iter=100
noise="mixed"

noisesets=/home/feiteng/openasr/datanoise/noisesets/combined/train

egs_dir=""
skip_train=false
skip_decode=false

stage=0
train_stage=0
srcdata=datanoise/trainsets/openasr500
num_epochs=2
exit_stage=

# gpus="0 1 2 3 4 5 6 7"
# nnet_jobs=8
gpus="0 1 2 3"
nnet_jobs=4

srcdir=exp/chain/tdnn_sp
cleandir=exp/chain/tdnn_sp
src_egs_combine=""
srciter=3000

egs_opts="--nj 6 --max-shuffle-jobs-run 10"
sort_egs_combine=true
percent=""
combine_egs_opts="--sort"

# fixstr="Tdnn_3_affine;Tdnn_4_affine;Tdnn_5_affine;Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
# fixstr="Tdnn_5_affine;Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
# fixstr="Tdnn_pre_final_chain_affine;Tdnn_pre_final_xent_affine;Final_affine;Final-xent_affine"
fix_layer_opts=""

deep_egs=false
decode_iters="final"

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

chmod +x -R local

splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"

initial_effective_lrate=0.0002
final_effective_lrate=0.00005
tree_dir=exp/chain/tri3_tree

mfccdir=datanoise/trainsets/mfcc_hires

# for snr in -15 -10 -5 0 5 10 15 20 25 30 35;do
for snr in 15;do
    echo "Start Training for SNR $snr"

    dir=exp/chainnoise/tdnn_sp_snr${snr}_nois_${noise}$suffix
    mkdir -p $dir

    if $deep_egs;then
        combined_lat_dir=exp/tri3_noise_combined_lats
        combined_data_dir=datanoise/trainsets/combine_snr-10to15
        if [ -z $egs_dir ];then
            lat_dirs=""
            # if [ ! -d $combined_data_dir ];then
            if true;then
                data_dirs=""
                
                for snr in -10 -5 0 5 10 15;do
                    # suffix data_dir lat_dir
                    # utils/data/copy_data_dir.sh --utt-suffix "_snr${snr}" datanoise/trainsets/openasr500-snr${snr}-noise-mixed tmp/openasr500-snr${snr}-noise-mixed
                    # utils/data/copy_lat_dir.sh --utt-suffix "_snr${snr}" exp/tri3_all_lats tmp/tri3_snr${snr}_lats || exit 1;
                    data_dirs="$data_dirs tmp/openasr500-snr${snr}-noise-mixed"
                    lat_dirs="$lat_dirs tmp/tri3_snr${snr}_lats"
                done
                # utils/data/combine_data.sh $combined_data_dir $data_dirs || exit 1;
                # steps/combine_lat_dirs.sh $combined_data_dir $combined_lat_dir $lat_dirs || exit 1;
            fi
            # utils/data/copy_data_dir.sh --utt-suffix "_snr_clean" datanoise/trainsets/openasr500 datanoise/trainsets/openasr500_snr_clean
            # utils/data/copy_lat_dir.sh --utt-suffix "_snr_clean" exp/tri3_all_lats tmp/tri3_snr_clean_lats || exit 1;

            # utils/data/combine_data.sh ${combined_data_dir}_clean $combined_data_dir datanoise/trainsets/openasr500_snr_clean || exit 1;
            steps/combine_lat_dirs.sh ${combined_data_dir}_clean ${combined_lat_dir}_clean $lat_dirs exp/tri3_all_lats || exit 1;
        fi
        echo "train_data_dir=${combined_data_dir}_clean" >$dir/vars
        echo "lat_dir=${combined_lat_dir}_clean" >>$dir/vars
    else
        train_set=${srcdata}-snr$[$snr]-noise-$noise
        echo "train_data_dir=$train_set" >$dir/vars
        echo "lat_dir=exp/tri3_all_lats" >>$dir/vars
        if [ -z $egs_dir ];then
            if $sort_egs_combine;then
                if [ ! -f $dir/egs_combine/.done ];then 
                    snr_egs_dirs=""
                    for snr in -10 -5 0 5 10 15;do #for snr in -15 -10 -5 0 5 10 15;do
                        snr_egs_dirs="$snr_egs_dirs exp/chainnoise/tdnn_sp_snr${snr}_nois_mixed_hour500_accan/egs"
                    done

                    steps/nnet3/combine_egs.py $combine_egs_opts --percent "$percent" $combine_egs_opts $snr_egs_dirs $dir/egs_combine >&$dir/egs_combine.log || exit 1;
                fi
                egs_dir=$dir/egs_combine
            fi
        fi

        if [ -z $egs_dir ];then
            if [ ! -f $dir/egs_combine/.done ];then
                echo "Combine Egs: $srcdir/egs(_combine) + $dir/egs -> $dir/egs_combine"
                if [ -f $srcdir/egs_combine/.done ];then
                    steps/nnet3/combine_egs.py $srcdir/egs_combine $dir/egs $dir/egs_combine || exit 1;
                elif [ ! -z $src_egs_combine ];then
                    steps/nnet3/combine_egs.py $src_egs_combine $dir/egs $dir/egs_combine || exit 1;
                else
                    steps/nnet3/combine_egs.py $srcdir/egs $dir/egs $dir/egs_combine || exit 1;
                fi
            else
                echo "Egs exist at: $dir/egs_combine"
            fi
            egs_dir=$dir/egs_combine
        fi

        if [ -f $egs_dir/.done ];then
            echo "Use Egs: $egs_dir"
            sleep 5
        elif [ -f $dir/egs/.done ];then
            egs_dir=$dir/egs
        else
            echo "Cann't Find Egs!"
            exit 1;
        fi
    fi

    cp exp/chainnoise/tdnn_sp_snr15_nois_mixed_hour500_accan_shuffleegs_snr-15to15/den.fst $dir || exit 1;
    bash copy_train_dir.sh --fix-layer "$fix_layer_opts" --iter $srciter --start-iter $start_iter $srcdir $dir

    if [[ $stage -le 10 && ! -f $dir/final.mdl ]];then
        bash local/chain/run_tdnn.sh --stage 10 --train-stage $train_stage --exit-stage "$exit_stage" \
            --adapt-stage $start_iter --cleanup true \
            --gpus "$gpus" --nnet-jobs $nnet_jobs --tree-dir $tree_dir \
            --frame-subsampling-factor 3 --pruner-perlayer 0 --pruner-times "" \
            --initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate \
            --extra-egs-dirs "" --get-egs-stage 0 --num-epochs $num_epochs --common-egs-dir "$egs_dir" --dir $dir || exit 1;
    fi
    # echo "496666" | sudo -S nvidia-smi -c 0
    cmvn_scp=data/train_sp_min1.55_hires/cmvn.scp.sub10k
    # sort -r $data/$train/cmvn.scp | head -n 10000 >$cmvn_scp
    graph_dir=exp/chain/tdnn/graph_tg

    echo "496666" | sudo -S nvidia-smi -c 0

    if ! $skip_decode;then
        (
            for snr in -15 -5 0 5 10 15;do
                snr_sets="snr$snr-noise-mixed"
                for decode_iter in $decode_iters;do
                    bash local/decode/online_decode.sh --decode-nj 1 --graph-dir $graph_dir \
                        --data datanoise/testsets --decode-iter $decode_iter \
                        --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                        --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
                        --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
                        --decode-sets "$snr_sets" --decode-opts "--stage 0" \
                        $dir &
                done
                sleep 50
            done
            wait

            # for snr in 0 15 20 25;do
            for snr in 20 25;do
                snr_sets="snr$snr-noise-mixed"
                for decode_iter in $decode_iters;do
                    bash local/decode/online_decode.sh --decode-nj 2 --graph-dir $graph_dir \
                        --data datanoise/testsets --decode-iter $decode_iter \
                        --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                        --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
                        --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
                        --decode-sets "$snr_sets" --decode-opts "--stage 0" \
                        $dir &
                done
                sleep 50
            done

            for decode_iter in $decode_iters;do
                bash local/decode/online_decode.sh --decode-nj 2 --graph-dir $graph_dir \
                    --data datanoise/testsets --decode-iter $decode_iter \
                    --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                    --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
                    --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
                    --decode-sets "clean" --decode-opts "--stage 0" \
                    $dir &
            done
            wait
        )
        echo "Decode DONE!"

    fi

    wait
done

kill $(jobs -p)

echo "$0: DONE!"

exit 0;
