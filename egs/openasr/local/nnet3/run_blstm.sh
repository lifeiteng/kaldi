stage=0
train_stage=-10
num_epochs=4
realign_times=""

affix=bidirectional
common_egs_dir=
remove_egs=false

# BLSTM params
cell_dim=512
rp_dim=128
nrp_dim=128
chunk_left_context=40
chunk_right_context=40

# training options
initial_effective_lrate=0.0003
final_effective_lrate=0.00003
num_jobs_initial=3
num_jobs_final=6
samples_per_iter=20000
label_delay=0
num_lstm_layers=3
lstm_delay=" [-1,1] [-2,2] [-3,3] "
splice_indexes="-2,-1,0,1,2 0 0"
max_param_change=2.0

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "usage: local/nnet3/run_blstm.sh <graph-dir> <data-dir> <align-dir>"
   echo "e.g.:  "
   echo "main options (for others, see top of script file)"
   exit 1;
fi

graph_dir=$1
data=$2
ali_dir=$3

local/nnet3/run_lstm.sh --affix $affix \
                         --stage $stage \
                         --train-stage $train_stage \
                         --lstm-delay "${lstm_delay}" \
                         --num-lstm-layers ${num_lstm_layers} \
                         --label-delay ${label_delay} \
                         --cell-dim $cell_dim \
                         --recurrent-projection-dim $rp_dim \
                         --non-recurrent-projection-dim $nrp_dim \
                         --common-egs-dir "$common_egs_dir" \
                         --chunk-left-context $chunk_left_context \
                         --chunk-right-context $chunk_right_context \
                         --num-jobs-initial $num_jobs_initial \
                         --num-jobs-final $num_jobs_final \
                         --samples-per-iter $samples_per_iter \
                         --num-epochs "$num_epochs" \
                         --realign-times \"$realign_times\" \
                         --remove-egs $remove_egs \
                         --common-egs-dir $common_egs_dir \
                         --splice-indexes "${splice_indexes}" \
                         --initial-effective-lrate 0.0003 \
                         --final-effective-lrate 0.00003 \
                         --max-param-change $max_param_change \
                         $graph_dir $data $ali_dir

