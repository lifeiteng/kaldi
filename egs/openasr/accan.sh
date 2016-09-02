

suffix=""
start_iter=100
noise="mixed"

noisesets=/home/feiteng/openasr/datanoise/noisesets/combined/train

egs_dir=
skip_train=false
skip_decode=false

stage=0
train_stage=0
srcdata=datanoise/trainsets/openasr500
num_epochs=2
exit_stage=

# gpus="0 1 2 3 4 5 6 7"
# nnet_jobs=8
gpus="0 1 3"
nnet_jobs=3

srcdir=exp/chain/tdnn_sp
cleandir=exp/chain/tdnn_sp

srciter=3000
accan=true

egs_opts="--nj 20 --max-shuffle-jobs-run 40"

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

chmod +x -R local

splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"

initial_effective_lrate=0.0002
final_effective_lrate=0.00005
tree_dir=exp/chain/tri3_tree

mfccdir=datanoise/trainsets/mfcc_hires


if [ $stage -le -1 ];then
    snr=-5
    dir=exp/chainnoise/tdnn_sp_snr${snr}_nois_${noise}$suffix
    if [ ! -d $dir/configs ];then
        bash copy_train_dir.sh --start-iter $start_iter $srcdir $dir
    fi
    train_set=${srcdata}-snr${snr}-noise-$noise
    if [ ! -f $train_set/cmvn.scp ];then
        echo "Noise type: $noise, SNR: $snr"
        rm -rf $train_set
        local/noise/addnoise.py --snr-db $snr --noise $noise --noise-data-dir $noisesets \
            --input-data-dir ${srcdata} --output-data-dir $train_set || exit 1;
        for datadir in $train_set;do
            steps/make_mfcc.sh --nj 20 --mfcc-config conf/mfcc_hires.conf \
              --cmd "$train_cmd" $datadir exp/make_hires/$datadir $mfccdir || exit 1;
            steps/compute_cmvn_stats.sh $datadir exp/make_hires/$datadir $mfccdir || exit 1;
        done
    fi
    echo "train_data_dir=$train_set" >$dir/vars
    echo "lat_dir=exp/tri3_all_lats" >>$dir/vars
    mkdir -p $dir/egs
    bash local/chain/run_tdnn.sh --stage 10 --train-stage -10 --exit-stage 0 --adapt-stage $start_iter --cleanup false \
        --gpus "-1 -1 -1 -1" --nnet-jobs 4 --tree-dir $tree_dir \
        --frame-subsampling-factor 3 --pruner-perlayer 0 --pruner-times "" \
        --initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate \
        --extra-egs-dirs "" --get-egs-stage 0 --egs-opts "$egs_opts" --num-epochs $num_epochs --common-egs-dir "" \
        --dir $dir --skip-train false || exit 1;

    # new_egs_dir=/ssd/`basename $dir`
    # mkdir -p $new_egs_dir
    # mv $dir/egs $new_egs_dir
    # ln -s $new_egs_dir/egs $dir/egs
    if [ -d $srcdir/egs_combine ];then
        steps/nnet3/combine_egs.py $srcdir/egs_combine $dir/egs $dir/egs_combine || exit 1;
    else
        steps/nnet3/combine_egs.py -C $srcdir/egs $dir/egs $dir/egs_combine || exit 1;
    fi
    echo "Prepare for SNR $snr DONE!"
fi

# for snr in -15 -10 -5 0 5 10 15 20 25 30 35;do
for snr in 15 20 25 30 35;do
    echo "Start Training for SNR $snr"
    if [ $snr -eq 15 ];then
        train_stage=369
    else
        train_stage=0
    fi

    (
        if [[ $stage -le 0 && $snr -le 30 ]];then # pre-computate Egs for next training
            dir=exp/chainnoise/tdnn_sp_snr$[$snr+5]_nois_${noise}$suffix
            if [ ! -d $dir/configs ];then
                bash copy_train_dir.sh --iter $srciter --start-iter $start_iter $srcdir $dir || exit 1;
            fi

            sleep 10
            train_set=${srcdata}-snr$[$snr+5]-noise-$noise
            if [ ! -f $train_set/cmvn.scp ];then
                echo "Noise type: $noise, SNR: $snr"
                rm -rf $train_set
                local/noise/addnoise.py --snr-db $[$snr+5] --noise $noise --noise-data-dir $noisesets \
                    --input-data-dir ${srcdata} --output-data-dir $train_set || exit 1;
                for datadir in $train_set;do
                    steps/make_mfcc.sh --nj 20 --mfcc-config conf/mfcc_hires.conf \
                      --cmd "$train_cmd" $datadir exp/make_hires/$datadir $mfccdir || exit 1;
                    steps/compute_cmvn_stats.sh $datadir exp/make_hires/$datadir $mfccdir || exit 1;
                done
            fi
            echo "train_data_dir=$train_set" >$dir/vars
            echo "lat_dir=exp/tri3_all_lats" >>$dir/vars
            if [ ! -f $dir/egs/.done ];then
                mkdir -p $dir/egs
                bash local/chain/run_tdnn.sh --stage 10 --train-stage -10 --exit-stage 0 --adapt-stage $start_iter --cleanup false \
                    --gpus "-1 -1 -1 -1" --nnet-jobs 4 --tree-dir $tree_dir \
                    --get-egs-stage 0 --egs-opts "$egs_opts" --num-epochs 2 --common-egs-dir "" \
                    --dir $dir || exit 1;
            fi
            echo "Prepare egs for SNR $[$snr+5] Done!"
        fi
    )
    continue

    dir=exp/chainnoise/tdnn_sp_snr${snr}_nois_${noise}$suffix
    bash copy_train_dir.sh --iter $srciter --start-iter $start_iter $srcdir $dir

    # if $accan && [ $snr -eq 35 ];then
    #     echo "Combine Egs: $srcdir/egs_combine + $cleandir/egs + $dir/egs -> $dir/egs_combine"
    #     steps/nnet3/combine_egs.py -C $srcdir/egs_combine $cleandir/egs $dir/egs $dir/egs_combine || exit 1;
    # fi

    egs_dir=/ssd/`basename $dir`-egs-combine
    if $accan;then
        if [ ! -f $dir/egs_combine/.done ];then
            echo "Combine Egs: $srcdir/egs(_combine) + $dir/egs -> $dir/egs_combine"
            mkdir -p $egs_dir
            rm -rf $dir/egs_combine
            ln -sf $egs_dir $dir/egs_combine
            if [ -f $srcdir/egs_combine/.done ];then
                steps/nnet3/combine_egs.py $srcdir/egs_combine $dir/egs $dir/egs_combine || exit 1
            else
                steps/nnet3/combine_egs.py $srcdir/egs $dir/egs $dir/egs_combine || exit 1;
            fi
        else
            echo "Egs exist at: $dir/egs_combine"
        fi         
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

    if [ ! -f $dir/final.mdl ];then
        bash local/chain/run_tdnn.sh --stage 10 --train-stage $train_stage --exit-stage "$exit_stage" \
            --adapt-stage $start_iter --cleanup false \
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
            for snr in 5 10 15 20 25;do
                snr_sets="snr$snr-noise-mixed"
                for decode_iter in final;do
                    bash local/decode/online_decode.sh --decode-nj 4 --graph-dir $graph_dir \
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

            for snr in -15 -5 0;do
                snr_sets="snr$snr-noise-mixed"
                for decode_iter in final;do
                    bash local/decode/online_decode.sh --decode-nj 4 --graph-dir $graph_dir \
                        --data datanoise/testsets --decode-iter $decode_iter \
                        --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
                        --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
                        --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
                        --decode-sets "$snr_sets" --decode-opts "--stage 0" \
                        $dir &
                done
                sleep 50
            done

            for decode_iter in final;do
                bash local/decode/online_decode.sh --decode-nj 4 --graph-dir $graph_dir \
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

    # Accordion Annealing Training
    if $accan;then
        srciter=final
        srcdir=$dir
    fi
done

kill $(jobs -p)

echo "$0: DONE!"

exit 0;
