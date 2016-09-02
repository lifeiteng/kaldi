

. ./path.sh

chmod +x -R local

start_iter=final



if [ ! -d exp/chainnoise/tdnn_sp_clean ];then
    bash copy_train_dir.sh --start-iter $start_iter exp/chain/tdnn_sp exp/chainnoise/tdnn_sp_clean
fi

echo "496666" | sudo -S nvidia-smi -c 0
cmvn_scp=data/train_sp_min1.55_hires/cmvn.scp.sub10k
# sort -r $data/$train/cmvn.scp | head -n 10000 >$cmvn_scp

dir=exp/chainnoise/tdnn_sp_clean
graph_dir=exp/chain/tdnn/graph_tg


# for snr in 5 10 15 20 25;do
#     snr_sets="snr$snr-noise-bus  snr$snr-noise-home  snr$snr-noise-mixed"
#     for decode_iter in $start_iter;do
#         bash local/decode/online_decode.sh --decode-nj 4 --graph-dir $graph_dir \
#             --data datanoise/testsets --decode-iter $decode_iter \
#             --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
#             --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
#             --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
#             --decode-sets "$snr_sets" --decode-opts "--stage 0" \
#             $dir &
#     done
# done

# for x in clean snr5_nois_bus_hour500 snr10_nois_bus_hour500 snr5_nois_home_hour500 snr10_nois_home_hour500;do

for x in clean snr10_nois_home_hour500 snr5_nois_home_hour500;do
    dir=exp/chainnoise/tdnn_sp_$x
    for snr in -15 -5 0;do
        snr_sets="snr$snr-noise-bus  snr$snr-noise-home  snr$snr-noise-mixed"
        bash local/decode/online_decode.sh --decode-nj 5 --graph-dir $graph_dir \
            --data datanoise/testsets --decode-iter "final" \
            --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
            --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
            --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
            --decode-sets "$snr_sets" --decode-opts "--stage 0" \
            $dir || exit 1;
    done
done

for x in snr10_nois_mixed_hour500_accan;do
    dir=exp/chainnoise/tdnn_sp_$x
    for snr in -15 -5 0;do
        snr_sets="snr$snr-noise-mixed"
        bash local/decode/online_decode.sh --decode-nj 6 --graph-dir $graph_dir \
            --data datanoise/testsets --decode-iter "final" \
            --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
            --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires.conf"  \
            --decode-suffix "" --chain true --scoring-opts "--min-lmwt 5 " \
            --decode-sets "$snr_sets" --decode-opts "--stage 0" \
            $dir || exit 1;
    done
done
exit 0;
