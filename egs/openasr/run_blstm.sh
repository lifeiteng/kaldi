

stage=0
train_stage=100

echo "$0 $@"  # Print the command line for logging

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

graphdir=exp/tri3/graph_tg
aligndir=exp/tri3_ali 
data=data_all_fbank

#------------------------------------------------------------------------------------------------------------------------------------
# Nnet3 systems
chmod +x local/nnet3/*
chmod +x local/nnet3/*/*
# BLSTM 
echo "496666" | sudo -S nvidia-smi -c 1
echo "496666" | sudo -S nvidia-smi -i 1 -c 1
echo "496666" | sudo -S nvidia-smi -i 2 -c 1

egs_dir=/ssd/fbank-ld0-lc42-lc22-egs/egs
num_lstm_layers=3
lstm_delay=" [-1,1] [-2,2] [-3,3] "
splice_indexes="-2,-1,0,1,2 0 0"

# num_lstm_layers=2
# lstm_delay=" [-1,1] [-2,2] "
# splice_indexes="-2,-1,0,1,2 0"

# BLSTM params
cell_dim=512
rp_dim=128
nrp_dim=128
max_param_change=2.0

# BLSTM params
cell_dim=512
rp_dim=256
nrp_dim=256
max_param_change=20.0

local/nnet3/run_blstm.sh --stage $stage --train-stage $train_stage \
  --chunk-right-context 20 --label-delay 0 --common-egs-dir ${egs_dir} \
  --num-lstm-layers $num_lstm_layers --lstm-delay "$lstm_delay" --splice-indexes "${splice_indexes}" \
  --cell-dim $cell_dim --rp-dim $rp_dim --nrp-dim $nrp_dim \
  --max-param-change $max_param_change \
  $graphdir $data $aligndir

# Note: Chunk right context of 20 limits the latency of the acoustic model to
# 20 frames.
