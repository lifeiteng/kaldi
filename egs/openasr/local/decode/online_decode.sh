
stage=1

# feat_config=" --feature-type mfcc --mfcc-config conf/mfcc_hires.conf "
feat_config=" --feature-type fbank --fbank-config conf/fbank.conf "
data=data_fbank
ctx_opts=

decode_sets="forum non-native native"
decode_iter="final"
decode_suffix=""

decode_opts=""
scoring_opts=""

graph_dir=exp/tri2b/graph_lang_biglm_tg
decode_nj=6

chain=false

online_cmvn_opts=""
# End configuration section.
echo "$0 $@"  # Print the command line for logging

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if [ $# != 1 ]; then
   echo "Usage: $0 [options] <model-dir>"
   echo "e.g.: $0 exp/chain/tdnn"
   echo ""
   echo ""
   echo "main options (for others, see top of script file)"
   echo "  --feat-config <config-file>                      # config containing options"
   echo "  --graph-dir <graph-dir>                          # decode graph"
   echo "  --decode-nj <nj>                                 # number of parallel jobs"
   echo "  --decode-iter <iter>                             # Iteration of model to decode; default is final."
   exit 1;
fi

dir=$1

if [[ $stage -le 1 && ! -f ${dir}_online/conf/global_cmvn.stats ]]; then
    steps/online/nnet3/prepare_online_decoding.sh $online_cmvn_opts $ctx_opts --iter $decode_iter $feat_config \
        $data/lang $dir ${dir}_online || exit 1;
else
  cp $dir/$decode_iter.mdl ${dir}_online || exit 1;
fi

if [ $stage -le 2 ]; then
    iter_opts=
    if [ ! -z $decode_iter ]; then
        iter_opts=" --iter $decode_iter "
    fi

    if $chain;then
        decode_opts="$decode_opts --acwt 1.0 --post-decode-acwt 10.0"
    fi

    for decode_set in $decode_sets; do
        steps/online/nnet3/decode.sh $decode_opts --scoring-opts "$scoring_opts" \
            --nj $decode_nj --cmd "$decode_cmd" $iter_opts --config conf/decode_online.config \
            $graph_dir $data/${decode_set} ${dir}_online/decode_${decode_iter}_${decode_set}${decode_suffix} || exit 1;

        # steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
        #     data/lang_sw1_{tg,fsh_fg} data/${decode_set}_hires \
        #     ${dir}_online/decode_${decode_set}${decode_iter:+_$decode_iter}_sw1_{tg,fsh_fg} || exit 1;
    done
fi
